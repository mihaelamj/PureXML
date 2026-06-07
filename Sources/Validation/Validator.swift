public extension PureXML.Validation {
    /// Path-aware validation over a parsed XML tree.
    ///
    /// The default validator checks structural rules that do not depend on a
    /// schema: an element must not declare the same attribute name twice. Schema
    /// (DTD, XSD, RELAX NG) validation is intentionally out of scope for the
    /// library target and is layered on by callers.
    struct Validator: Sendable {
        public init() {}

        /// Collects validation issues for a node tree.
        public func collect(_ node: PureXML.Model.Node) -> [Issue] {
            var issues: [Issue] = []
            walk(node, into: &issues)
            return issues
        }

        /// Validates a node tree, throwing the first error-severity issue.
        @discardableResult
        public func validate(_ node: PureXML.Model.Node, strict: Bool = true) throws -> [Issue] {
            let issues = collect(node)
            if let error = issues.first(where: { $0.severity == .error }) {
                throw error
            }
            if strict, let warning = issues.first(where: { $0.severity == .warning }) {
                throw warning
            }
            return issues
        }

        private func walk(_ node: PureXML.Model.Node, into issues: inout [Issue]) {
            switch node {
            case let .document(children):
                for child in children {
                    walk(child, into: &issues)
                }
            case let .element(element):
                var seen: Set<String> = []
                for attribute in element.attributes {
                    let key = attribute.name.description
                    if !seen.insert(key).inserted {
                        issues.append(.init(
                            severity: .error,
                            message: "duplicate attribute '\(key)' on <\(element.name.description)>",
                        ))
                    }
                }
                for child in element.children {
                    walk(child, into: &issues)
                }
            case .text, .cdata, .comment, .processingInstruction:
                break
            }
        }
    }
}

extension PureXML.Validation.Issue: Swift.Error {}
