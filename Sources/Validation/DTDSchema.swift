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

        /// Validates a node tree against the declared content models. In strict
        /// mode an element with no declaration is itself an error; otherwise
        /// undeclared elements are skipped.
        public func validate(_ node: PureXML.Model.Node, strict: Bool = false) -> [Issue] {
            var issues: [Issue] = []
            walk(node, strict: strict, into: &issues)
            return issues
        }

        private func walk(_ node: PureXML.Model.Node, strict: Bool, into issues: inout [Issue]) {
            switch node {
            case let .document(children):
                for child in children {
                    walk(child, strict: strict, into: &issues)
                }
            case let .element(element):
                validateElement(element, strict: strict, into: &issues)
                for child in element.children {
                    walk(child, strict: strict, into: &issues)
                }
            case .text, .cdata, .comment, .processingInstruction:
                break
            }
        }

        private func validateElement(_ element: PureXML.Model.Element, strict: Bool, into issues: inout [Issue]) {
            let name = element.name.description
            if let model = models[name] {
                let content = childContent(of: element)
                issues.append(contentsOf: violations(name: name, model: model, content: content))
            } else if strict {
                issues.append(error("element <\(name)> is not declared in the DTD"))
            }
            issues.append(contentsOf: attributeViolations(name: name, element: element))
        }

        private func attributeViolations(name: String, element: PureXML.Model.Element) -> [Issue] {
            guard let declarations = attributes[name] else { return [] }
            var result: [Issue] = []
            for declaration in declarations {
                let value = element.attributes.first {
                    $0.name.description == declaration.name || $0.name.localName == declaration.name
                }?.value
                result.append(contentsOf: checkAttribute(declaration, value: value, on: name))
            }
            return result
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
