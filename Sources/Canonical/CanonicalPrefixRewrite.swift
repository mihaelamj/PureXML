/// A mutable bag of rebuilt nodes a branch's children gather into, so the
/// canonical prefix rewrite's deferred build step assembles the parent once they
/// are done.
private final class CanonicalRewriteAccumulator {
    var nodes: [PureXML.Model.Node] = []
}

/// One unit of canonical prefix-rewrite work: visit a source node (appending its
/// rebuilt result to `target`), or, after a branch's children are gathered, build
/// the element or document. File-scoped so the work stack is not a third level of
/// type nesting.
private enum CanonicalRewriteWork {
    case visit(PureXML.Model.Node, inScope: [String: String], isRoot: Bool, target: CanonicalRewriteAccumulator)
    case buildElement(PureXML.Model.Element, childInScope: [String: String], isRoot: Bool, gathered: CanonicalRewriteAccumulator, target: CanonicalRewriteAccumulator)
    case buildDocument(CanonicalRewriteAccumulator, CanonicalRewriteAccumulator)
}

extension PureXML.Canonical {
    /// The Canonical XML 2.0 sequential prefix rewrite. Implemented as a pre-pass
    /// that rebuilds the tree using canonical prefixes (`n0`, `n1`, ... in
    /// document order of first use), drops the original namespace declarations,
    /// and hoists one canonical declaration per namespace onto the document
    /// element. The rewritten tree is then rendered exclusive-style so each
    /// declaration appears at the first element that uses it, with no default
    /// namespace (every name carries a prefix). The reserved `xml` prefix is left
    /// untouched.
    enum PrefixRewriter {
        private static let xmlNamespace = "http://www.w3.org/XML/1998/namespace"

        /// Rewrites a node tree's prefixes (and any QName-valued labels) to their
        /// canonical sequential form.
        static func rewrite(_ node: PureXML.Model.Node, labels: [QNameAwareLabel]) -> PureXML.Model.Node {
            var assignment: [String: String] = [:]
            var order = 0
            assign(node, inScope: [:], labels: labels, &assignment, &order)
            return transform(node, assignment: assignment, labels: labels)
        }

        // MARK: First pass: assign a canonical prefix per visibly-used namespace

        private static func assign(
            _ root: PureXML.Model.Node,
            inScope: [String: String],
            labels: [QNameAwareLabel],
            _ assignment: inout [String: String],
            _ order: inout Int,
        ) {
            // Iterative pre-order walk so a deeply-nested document does not overflow
            // the stack; children push reversed so namespaces are recorded in
            // document order, the order the canonical prefixes n0, n1, ... assign in.
            var stack: [(node: PureXML.Model.Node, inScope: [String: String])] = [(root, inScope)]
            while let (node, inScope) = stack.popLast() {
                switch node {
                case let .document(children):
                    for child in children.reversed() {
                        stack.append((child, inScope))
                    }
                case let .element(element):
                    var childInScope = inScope
                    for (prefix, uri) in declarations(element) {
                        childInScope[prefix] = uri
                    }
                    record(element.name.namespaceURI, &assignment, &order)
                    for attribute in element.attributes where attribute.name.prefix != nil {
                        record(attribute.name.namespaceURI, &assignment, &order)
                    }
                    for attribute in element.attributes where isQNameAttribute(attribute.name, labels) {
                        record(qnameNamespace(attribute.value, inScope: childInScope), &assignment, &order)
                    }
                    record(qnameNamespace(element.text(matching: labels), inScope: childInScope), &assignment, &order)
                    for child in element.children.reversed() {
                        stack.append((child, childInScope))
                    }
                default:
                    break
                }
            }
        }

        /// The namespace URI a QName value refers to through its prefix, or nil.
        private static func qnameNamespace(_ value: String?, inScope: [String: String]) -> String? {
            guard let value else { return nil }
            let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            return inScope[parts.count == 2 ? String(parts[0]) : ""]
        }

        private static func isQNameAttribute(_ name: PureXML.Model.QualifiedName, _ labels: [QNameAwareLabel]) -> Bool {
            labels.contains { !$0.isElement && $0.localName == name.localName && $0.namespaceURI == (name.namespaceURI ?? "") }
        }

        private static func record(_ uri: String?, _ assignment: inout [String: String], _ order: inout Int) {
            guard let uri, uri != xmlNamespace, assignment[uri] == nil else { return }
            assignment[uri] = "n\(order)"
            order += 1
        }

        // MARK: Second pass: rebuild with canonical prefixes

        /// Rebuilds the tree with canonical prefixes without recursing on its depth.
        /// An explicit work stack threads the in-scope declarations and the root
        /// flag down per element, while each branch gathers its rebuilt children
        /// into a reference accumulator that a deferred build step assembles, so a
        /// deeply-nested document does not overflow the stack.
        private static func transform(
            _ root: PureXML.Model.Node,
            assignment: [String: String],
            labels: [QNameAwareLabel],
        ) -> PureXML.Model.Node {
            let result = CanonicalRewriteAccumulator()
            var stack: [CanonicalRewriteWork] = [.visit(root, inScope: [:], isRoot: true, target: result)]
            while let work = stack.popLast() {
                switch work {
                case let .visit(node, inScope, isRoot, target):
                    visitForRewrite(node, inScope: inScope, isRoot: isRoot, target: target, stack: &stack)
                case let .buildElement(element, childInScope, isRoot, gathered, target):
                    var attributes = isRoot ? canonicalDeclarations(assignment) : []
                    for attribute in element.attributes where declaredPrefix(of: attribute.name) == nil {
                        attributes.append(rewrite(attribute, inScope: childInScope, assignment: assignment, labels: labels))
                    }
                    // A QName-labelled element's single text child is rewritten to a
                    // canonical-prefixed QName, replacing its rebuilt children.
                    let qualified = qname(element.text(matching: labels), inScope: childInScope, assignment: assignment)
                    target.nodes.append(.element(PureXML.Model.Element(
                        name: rename(element.name, assignment: assignment),
                        attributes: attributes,
                        children: qualified.map { [PureXML.Model.Node.text($0)] } ?? gathered.nodes,
                    )))
                case let .buildDocument(gathered, target):
                    target.nodes.append(.document(gathered.nodes))
                }
            }
            return result.nodes.first ?? root
        }

        /// Pushes a node's rebuild work: a document or element schedules its build
        /// step then its children (with the in-scope declarations extended), a leaf
        /// is appended to `target` unchanged.
        private static func visitForRewrite(
            _ node: PureXML.Model.Node,
            inScope: [String: String],
            isRoot: Bool,
            target: CanonicalRewriteAccumulator,
            stack: inout [CanonicalRewriteWork],
        ) {
            switch node {
            case let .document(children):
                let gathered = CanonicalRewriteAccumulator()
                stack.append(.buildDocument(gathered, target))
                for child in children.reversed() {
                    stack.append(.visit(child, inScope: inScope, isRoot: isRoot, target: gathered))
                }
            case let .element(element):
                var childInScope = inScope
                for (prefix, uri) in declarations(element) {
                    childInScope[prefix] = uri
                }
                let gathered = CanonicalRewriteAccumulator()
                stack.append(.buildElement(element, childInScope: childInScope, isRoot: isRoot, gathered: gathered, target: target))
                for child in element.children.reversed() {
                    stack.append(.visit(child, inScope: childInScope, isRoot: false, target: gathered))
                }
            default:
                target.nodes.append(node)
            }
        }

        /// One `xmlns:nK="uri"` declaration per assigned namespace, hoisted to the
        /// document element so every canonical prefix is in scope from the top.
        private static func canonicalDeclarations(_ assignment: [String: String]) -> [PureXML.Model.Attribute] {
            assignment.sorted { $0.value < $1.value }.map { uri, prefix in
                PureXML.Model.Attribute("xmlns:\(prefix)", uri)
            }
        }

        private static func rewrite(
            _ attribute: PureXML.Model.Attribute,
            inScope: [String: String],
            assignment: [String: String],
            labels: [QNameAwareLabel],
        ) -> PureXML.Model.Attribute {
            let name = rename(attribute.name, assignment: assignment)
            guard isQNameAttribute(attribute.name, labels), let value = qname(attribute.value, inScope: inScope, assignment: assignment) else {
                return PureXML.Model.Attribute(name: name, value: attribute.value)
            }
            return PureXML.Model.Attribute(name: name, value: value)
        }

        /// A qualified name with its prefix replaced by the canonical one. Returns
        /// nil when there is nothing to rewrite (no bound prefix for the value).
        private static func qname(_ value: String?, inScope: [String: String], assignment: [String: String]) -> String? {
            guard let value else { return nil }
            let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let prefix = parts.count == 2 ? String(parts[0]) : ""
            let local = parts.count == 2 ? String(parts[1]) : value
            guard let uri = inScope[prefix], let canonical = assignment[uri] else { return nil }
            return "\(canonical):\(local)"
        }

        private static func rename(_ name: PureXML.Model.QualifiedName, assignment: [String: String]) -> PureXML.Model.QualifiedName {
            guard let uri = name.namespaceURI, uri != xmlNamespace, let canonical = assignment[uri] else { return name }
            return PureXML.Model.QualifiedName(prefix: canonical, localName: name.localName, namespaceURI: uri)
        }

        private static func declarations(_ element: PureXML.Model.Element) -> [(String, String)] {
            element.attributes.compactMap { attribute in
                declaredPrefix(of: attribute.name).map { ($0, attribute.value) }
            }
        }

        private static func declaredPrefix(of name: PureXML.Model.QualifiedName) -> String? {
            if name.prefix == nil, name.localName == "xmlns" { return "" }
            if name.prefix == "xmlns" { return name.localName }
            return nil
        }
    }
}

extension PureXML.Model.Element {
    /// The text content of this element when it is labelled QName-aware as an
    /// element (a single text child holding a QName), or nil otherwise.
    func text(matching labels: [PureXML.Canonical.QNameAwareLabel]) -> String? {
        guard labels.contains(where: { $0.isElement && $0.localName == name.localName && $0.namespaceURI == (name.namespaceURI ?? "") }) else { return nil }
        guard children.count == 1, case let .text(value) = children[0] else { return nil }
        return value
    }
}
