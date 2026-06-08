public extension PureXML.Validation {
    /// A DTD schema: the element content models declared by `<!ELEMENT>` and the
    /// attribute declarations from `<!ATTLIST>`, against which a parsed tree can
    /// be validated. Built from the internal subset surfaced by the parser.
    struct DTDSchema: Sendable {
        let models: [String: ContentModel]
        let attributes: [String: [AttributeDeclaration]]

        init(_ documentType: PureXML.Parsing.DocumentType) {
            var parsedModels: [String: ContentModel] = [:]
            for (name, model) in documentType.elementModels {
                parsedModels[name] = ContentModelParser.parse(model)
            }
            models = parsedModels

            var parsedAttributes: [String: [AttributeDeclaration]] = [:]
            for (name, body) in documentType.attributeLists {
                parsedAttributes[name] = AttributeListParser.parse(body)
            }
            attributes = parsedAttributes
        }

        /// Whether the schema declares any elements or attributes.
        public var isEmpty: Bool {
            models.isEmpty && attributes.isEmpty
        }

        /// Validates a node tree against the declared content models and attribute
        /// rules. Element structure and attribute presence/value are checked in one
        /// walk; ID uniqueness and IDREF resolution are checked afterward, since a
        /// reference may point forward to an ID later in the document. In strict
        /// mode an element with no declaration is itself an error.
        public func validate(_ node: PureXML.Model.Node, strict: Bool = false) -> [Issue] {
            var state = DTDState()
            walk(node, strict: strict, into: &state)
            for (value, count) in state.idCounts where count > 1 {
                state.issues.append(error("duplicate ID '\(value)' (declared \(count) times)"))
            }
            for reference in state.references where state.idCounts[reference.value] == nil {
                state.issues.append(error("IDREF '\(reference.value)' on <\(reference.element)> matches no ID"))
            }
            return state.issues
        }

        private func walk(_ node: PureXML.Model.Node, strict: Bool, into state: inout DTDState) {
            switch node {
            case let .document(children):
                for child in children {
                    walk(child, strict: strict, into: &state)
                }
            case let .element(element):
                validateElement(element, strict: strict, into: &state)
                for child in element.children {
                    walk(child, strict: strict, into: &state)
                }
            case .text, .cdata, .comment, .processingInstruction:
                break
            }
        }

        private func validateElement(_ element: PureXML.Model.Element, strict: Bool, into state: inout DTDState) {
            let name = element.name.description
            if let model = models[name] {
                let content = childContent(of: element)
                state.issues.append(contentsOf: violations(name: name, model: model, content: content))
            } else if strict {
                state.issues.append(error("element <\(name)> is not declared in the DTD"))
            }
            guard let declarations = attributes[name] else { return }
            for declaration in declarations {
                let value = element.attributes.first {
                    $0.name.description == declaration.name || $0.name.localName == declaration.name
                }?.value
                state.issues.append(contentsOf: checkAttribute(declaration, value: value, on: name))
                if let value {
                    collectIdentifiers(declaration, value: value, element: name, into: &state)
                }
            }
        }

        private func collectIdentifiers(
            _ declaration: AttributeDeclaration,
            value: String,
            element: String,
            into state: inout DTDState,
        ) {
            switch declaration.type {
            case .id:
                state.idCounts[value, default: 0] += 1
            case .idReference:
                state.references.append((value, element))
            case .idReferences:
                for token in value.split(whereSeparator: { $0.isWhitespace }) {
                    state.references.append((String(token), element))
                }
            case .cdata, .enumeration:
                break
            }
        }

        private func checkAttribute(_ declaration: AttributeDeclaration, value: String?, on element: String) -> [Issue] {
            guard let value else {
                return declaration.defaultDecl == .required
                    ? [error("required attribute '\(declaration.name)' is missing on <\(element)>")]
                    : []
            }
            var result: [Issue] = []
            if case let .fixed(fixedValue) = declaration.defaultDecl, value != fixedValue {
                result.append(error("attribute '\(declaration.name)' on <\(element)> is #FIXED and must be \"\(fixedValue)\""))
            }
            if case let .enumeration(allowed) = declaration.type, !allowed.contains(value) {
                result.append(error("attribute '\(declaration.name)' on <\(element)> has a value outside its enumeration"))
            }
            return result
        }

        private func childContent(of element: PureXML.Model.Element) -> (names: [String], hasText: Bool) {
            var names: [String] = []
            var hasText = false
            for child in element.children {
                switch child {
                case let .element(inner):
                    names.append(inner.name.description)
                case let .text(value), let .cdata(value):
                    if value.contains(where: { !$0.isWhitespace }) { hasText = true }
                default:
                    break
                }
            }
            return (names, hasText)
        }

        private func violations(name: String, model: ContentModel, content: (names: [String], hasText: Bool)) -> [Issue] {
            switch model {
            case .empty:
                content.names.isEmpty && !content.hasText
                    ? []
                    : [error("element <\(name)> is declared EMPTY but has content")]
            case .any:
                []
            case .pcdata:
                content.names.isEmpty
                    ? []
                    : [error("element <\(name)> is declared (#PCDATA) but has child elements")]
            case let .mixed(allowed):
                content.names
                    .filter { !allowed.contains($0) }
                    .map { error("element <\($0)> is not allowed in the mixed content of <\(name)>") }
            case let .children(particle):
                childrenViolations(name: name, particle: particle, content: content)
            }
        }

        private func childrenViolations(
            name: String,
            particle: Particle,
            content: (names: [String], hasText: Bool),
        ) -> [Issue] {
            var result: [Issue] = []
            if content.hasText {
                result.append(error("element <\(name)> has element content but contains character data"))
            }
            if !ContentModelMatcher.matchesChildren(particle, content.names) {
                result.append(error("the children of <\(name)> do not match its content model"))
            }
            return result
        }

        private func error(_ message: String) -> Issue {
            Issue(severity: .error, message: message)
        }
    }
}

/// Mutable state carried through one DTD validation walk: the issues found, the
/// count of each declared ID, and the IDREF references to resolve afterward.
private struct DTDState {
    var issues: [PureXML.Validation.Issue] = []
    var idCounts: [String: Int] = [:]
    var references: [(value: String, element: String)] = []
}
