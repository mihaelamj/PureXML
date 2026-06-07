public extension PureXML.Validation {
    /// A DTD schema: the element content models declared by `<!ELEMENT>`,
    /// against which a parsed tree can be validated. Built from the internal
    /// subset surfaced by the parser. Attribute-list (`<!ATTLIST>`) validation
    /// is not yet covered.
    struct DTDSchema: Sendable {
        let models: [String: ContentModel]

        init(elementModels: [String: String]) {
            var parsed: [String: ContentModel] = [:]
            for (name, model) in elementModels {
                parsed[name] = ContentModelParser.parse(model)
            }
            models = parsed
        }

        /// Whether the schema declares any elements.
        public var isEmpty: Bool {
            models.isEmpty
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
            guard let model = models[name] else {
                if strict {
                    issues.append(error("element <\(name)> is not declared in the DTD"))
                }
                return
            }
            let content = childContent(of: element)
            issues.append(contentsOf: violations(name: name, model: model, content: content))
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
