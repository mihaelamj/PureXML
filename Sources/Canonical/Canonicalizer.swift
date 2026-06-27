public extension PureXML.Canonical {
    /// Produces the Canonical XML (C14N) form of a node (the libxml2 `c14n.h`
    /// model): UTF-8 text with namespace declarations and attributes in canonical
    /// order, empty elements expanded to start/end pairs, character and attribute
    /// escaping normalized, and namespaces rendered per the inclusive or exclusive
    /// rules. Comments are omitted unless requested. Reimplemented from the C14N
    /// specification.
    struct Canonicalizer: Sendable {
        public let options: Options

        public init(options: Options = .inclusive) {
            self.options = options
        }

        /// Canonicalizes a node.
        public func canonicalize(_ node: PureXML.Model.Node) -> String {
            if options.prefixRewrite == .sequential {
                // C14N 2.0 sequential rewrite: rebuild with canonical prefixes,
                // then render exclusive-style so declarations land at first use.
                let rewritten = PrefixRewriter.rewrite(node, labels: options.qnameAwareLabels)
                var rendering = options
                rendering.prefixRewrite = .retain
                rendering.mode = .exclusive
                return Canonicalizer(options: rendering).canonicalize(rewritten)
            }
            var output = ""
            emit(node, inScope: [:], rendered: [:], output: &output)
            return output
        }

        /// Canonicalizes a subtree that may sit inside a larger document (the C14N
        /// node-subset case). The apex element receives the namespace context in
        /// scope from its omitted ancestors, and inherits their in-scope `xml:*`
        /// attributes (`xml:base`, `xml:lang`, `xml:space`) when it does not set
        /// them itself, so signing a fragment yields the same bytes regardless of
        /// where the fragment sat in the document. (Inherited `xml:base` follows
        /// the C14N 1.0 nearest-ancestor rule, not 1.1 URI joining.)
        public func canonicalize(_ subtree: PureXML.Model.TreeNode) -> String {
            guard subtree.kind == .element, case let .element(apex) = subtree.node else {
                return canonicalize(subtree.node)
            }
            let ancestorNamespaces = Self.inScopeNamespaces(above: subtree)
            let mergeBase = options.mergeInheritedBase
            let inheritedXML = Self.inheritedXMLAttributes(above: subtree, apex: apex, mergeBase: mergeBase)
            var output = ""
            switch options.mode {
            case .inclusive:
                let augmented = Self.augmentedApex(apex, inheritedXML: inheritedXML, mergingNamespaces: ancestorNamespaces, stripApexBase: mergeBase)
                emit(augmented, inScope: [:], rendered: [:], output: &output)
            case .exclusive:
                let augmented = Self.augmentedApex(apex, inheritedXML: inheritedXML, mergingNamespaces: nil, stripApexBase: mergeBase)
                emit(augmented, inScope: ancestorNamespaces, rendered: [:], output: &output)
            }
            return output
        }

        private func emit(
            _ node: PureXML.Model.Node,
            inScope: [String: String],
            rendered: [String: String],
            output: inout String,
        ) {
            switch node {
            case let .document(children):
                // Top-level comments, PIs, and the document element are
                // separated from one another by single line feeds.
                var renderings: [String] = []
                for child in children {
                    var rendering = ""
                    emit(child, inScope: inScope, rendered: rendered, output: &rendering)
                    if !rendering.isEmpty { renderings.append(rendering) }
                }
                output += renderings.joined(separator: "\n")
            case let .element(element):
                emit(element, inScope: inScope, rendered: rendered, output: &output)
            case let .text(value), let .cdata(value):
                let text = options.trimTextNodes ? value.trimmingXMLWhitespace() : value
                output += Self.escapeText(text)
            case let .comment(value):
                if options.includeComments { output += "<!--\(value)-->" }
            case let .processingInstruction(target, data):
                output += data.isEmpty ? "<?\(target)?>" : "<?\(target) \(data)?>"
            }
        }

        private func emit(
            _ element: PureXML.Model.Element,
            inScope: [String: String],
            rendered: [String: String],
            output: inout String,
        ) {
            // Deferred-close work stack so a deeply-nested element does not
            // overflow the stack; children push reversed to emit in document order.
            var stack: [CanonicalStep] = [.open(.element(element), inScope: inScope, rendered: rendered)]
            while let step = stack.popLast() {
                switch step {
                case let .close(name):
                    output += "</\(name)>"
                case let .open(node, inScope, rendered):
                    guard case let .element(element) = node else {
                        emitLeaf(node, into: &output)
                        continue
                    }
                    let child = emitOpenTag(element, inScope: inScope, rendered: rendered, into: &output)
                    stack.append(.close(element.name.description))
                    for childNode in element.children.reversed() {
                        stack.append(.open(childNode, inScope: child.inScope, rendered: child.rendered))
                    }
                }
            }
        }

        /// Emits an element's start tag (namespaces then attributes, in canonical
        /// order) and returns the namespace context its children inherit.
        private func emitOpenTag(
            _ element: PureXML.Model.Element,
            inScope: [String: String],
            rendered: [String: String],
            into output: inout String,
        ) -> (inScope: [String: String], rendered: [String: String]) {
            let declarations = Self.namespaceDeclarations(element)
            var childInScope = inScope
            for (prefix, uri) in declarations {
                childInScope[prefix] = uri
            }
            let attributes = Self.plainAttributes(element)
            let toRender = namespacesToRender(element, declarations: declarations, inScope: childInScope, attributes: attributes, rendered: rendered)
            var childRendered = rendered
            for (prefix, uri) in toRender {
                childRendered[prefix] = uri
            }

            output += "<" + element.name.description
            for (prefix, uri) in toRender.sorted(by: { $0.0 < $1.0 }) {
                output += Self.renderNamespace(prefix, uri)
            }
            for attribute in attributes.sorted(by: Self.attributeOrder) {
                output += " \(attribute.name.description)=\"\(Self.escapeAttribute(attribute.value))\""
            }
            output += ">"
            return (childInScope, childRendered)
        }

        /// Emits a non-element node (text, CDATA, comment, or processing
        /// instruction) the same way the node-level `emit` does.
        private func emitLeaf(_ node: PureXML.Model.Node, into output: inout String) {
            switch node {
            case let .text(value), let .cdata(value):
                let text = options.trimTextNodes ? value.trimmingXMLWhitespace() : value
                output += Self.escapeText(text)
            case let .comment(value):
                if options.includeComments { output += "<!--\(value)-->" }
            case let .processingInstruction(target, data):
                output += data.isEmpty ? "<?\(target)?>" : "<?\(target) \(data)?>"
            case .element, .document:
                break
            }
        }

        // MARK: Namespace selection

        private func namespacesToRender(
            _ element: PureXML.Model.Element,
            declarations: [(String, String)],
            inScope: [String: String],
            attributes: [PureXML.Model.Attribute],
            rendered: [String: String],
        ) -> [(String, String)] {
            switch options.mode {
            case .inclusive:
                declarations.filter { prefix, uri in
                    guard rendered[prefix] != uri else { return false }
                    // An empty default declaration is superfluous unless a
                    // non-empty default namespace was rendered above.
                    if prefix.isEmpty, uri.isEmpty {
                        return !(rendered[""] ?? "").isEmpty
                    }
                    return true
                }
            case .exclusive:
                exclusiveNamespaces(element, inScope: inScope, attributes: attributes, rendered: rendered)
            }
        }

        private func exclusiveNamespaces(
            _ element: PureXML.Model.Element,
            inScope: [String: String],
            attributes: [PureXML.Model.Attribute],
            rendered: [String: String],
        ) -> [(String, String)] {
            var utilized: Set<String> = [element.name.prefix ?? ""]
            for attribute in attributes where attribute.name.prefix != nil {
                utilized.insert(attribute.name.prefix ?? "")
            }
            utilized.formUnion(options.inclusiveNamespacePrefixes)

            var result: [(String, String)] = []
            for prefix in utilized {
                let uri = inScope[prefix] ?? ""
                if prefix.isEmpty {
                    if uri != (rendered[""] ?? "") { result.append(("", uri)) }
                } else if !uri.isEmpty, rendered[prefix] != uri {
                    result.append((prefix, uri))
                }
            }
            return result
        }

        // MARK: Attribute and namespace rendering

        private static func renderNamespace(_ prefix: String, _ uri: String) -> String {
            prefix.isEmpty ? " xmlns=\"\(escapeAttribute(uri))\"" : " xmlns:\(prefix)=\"\(escapeAttribute(uri))\""
        }

        private static func attributeOrder(_ lhs: PureXML.Model.Attribute, _ rhs: PureXML.Model.Attribute) -> Bool {
            let leftURI = lhs.name.namespaceURI ?? ""
            let rightURI = rhs.name.namespaceURI ?? ""
            if leftURI != rightURI { return leftURI < rightURI }
            return lhs.name.localName < rhs.name.localName
        }

        private static func namespaceDeclarations(_ element: PureXML.Model.Element) -> [(String, String)] {
            element.attributes.compactMap { attribute in
                let name = attribute.name
                if name.prefix == nil, name.localName == "xmlns" { return ("", attribute.value) }
                if name.prefix == "xmlns" { return (name.localName, attribute.value) }
                return nil
            }
        }

        private static func plainAttributes(_ element: PureXML.Model.Element) -> [PureXML.Model.Attribute] {
            element.attributes.filter { attribute in
                let name = attribute.name
                return name.prefix != "xmlns" && !(name.prefix == nil && name.localName == "xmlns")
            }
        }
    }
}

public extension PureXML.Canonical.Canonicalizer {
    /// Canonicalizes a node-set: only the nodes the predicate selects appear in
    /// the output (C14N's XPath/position-based node selection). An excluded
    /// element's start and end tags are omitted but its selected descendants are
    /// kept, with each one rendering the namespace context in scope at its
    /// position, so signing a discontiguous selection is well defined. Predicate
    /// identity is by ``PureXML/Model/TreeNode`` reference, so a caller can select
    /// specific nodes (for example an XPath result set).
    func canonicalize(_ node: PureXML.Model.TreeNode, including predicate: (PureXML.Model.TreeNode) -> Bool) -> String {
        var output = ""
        emitSelected(node, inScope: Self.inScopeNamespaces(above: node), rendered: [:], including: predicate, output: &output)
        return output
    }

    private func emitSelected(
        _ root: PureXML.Model.TreeNode,
        inScope: [String: String],
        rendered: [String: String],
        including predicate: (PureXML.Model.TreeNode) -> Bool,
        output: inout String,
    ) {
        // Deferred-close work stack so a deeply-nested subtree does not overflow
        // the stack; children push reversed to emit in document order, threading
        // each element's in-scope and already-rendered namespace context.
        var stack: [CanonicalSelectedStep] = [.open(root, inScope: inScope, rendered: rendered)]
        while let step = stack.popLast() {
            switch step {
            case let .close(name):
                output += "</\(name)>"
            case let .open(node, inScope, rendered):
                switch node.kind {
                case .document:
                    for child in node.children.reversed() {
                        stack.append(.open(child, inScope: inScope, rendered: rendered))
                    }
                case .element:
                    stack.append(contentsOf: selectedElementSteps(node, inScope: inScope, rendered: rendered, including: predicate, into: &output))
                default:
                    emitSelectedLeaf(node, including: predicate, into: &output)
                }
            }
        }
    }

    /// Emits a selected element's start tag and returns the steps to push for its
    /// subtree: its children to visit, preceded by a close step (so the close pops
    /// after them). An omitted element renders nothing and pushes no close, but its
    /// declarations still stay in scope for descendants, so a selected descendant
    /// re-declares them itself.
    private func selectedElementSteps(
        _ node: PureXML.Model.TreeNode,
        inScope: [String: String],
        rendered: [String: String],
        including predicate: (PureXML.Model.TreeNode) -> Bool,
        into output: inout String,
    ) -> [CanonicalSelectedStep] {
        let element = PureXML.Model.Element(name: node.name ?? .init(""), attributes: node.attributes, children: [])
        var childInScope = inScope
        for (prefix, uri) in Self.namespaceDeclarations(element) {
            childInScope[prefix] = uri
        }
        guard predicate(node) else {
            return node.children.reversed().map { .open($0, inScope: childInScope, rendered: rendered) }
        }
        let attributes = Self.plainAttributes(element)
        let toRender = selectedNamespaces(element, inScope: childInScope, attributes: attributes, rendered: rendered)
        var childRendered = rendered
        for (prefix, uri) in toRender {
            childRendered[prefix] = uri
        }
        output += "<" + element.name.description
        for (prefix, uri) in toRender.sorted(by: { $0.0 < $1.0 }) {
            output += Self.renderNamespace(prefix, uri)
        }
        for attribute in attributes.sorted(by: Self.attributeOrder) {
            output += " \(attribute.name.description)=\"\(Self.escapeAttribute(attribute.value))\""
        }
        output += ">"
        var steps: [CanonicalSelectedStep] = [.close(element.name.description)]
        steps.append(contentsOf: node.children.reversed().map { .open($0, inScope: childInScope, rendered: childRendered) })
        return steps
    }

    /// Emits a selected non-element node (text, CDATA, comment, or PI).
    private func emitSelectedLeaf(_ node: PureXML.Model.TreeNode, including predicate: (PureXML.Model.TreeNode) -> Bool, into output: inout String) {
        guard predicate(node) else { return }
        switch node.kind {
        case .text, .cdata:
            output += Self.escapeText(options.trimTextNodes ? node.value.trimmingXMLWhitespace() : node.value)
        case .comment:
            if options.includeComments { output += "<!--\(node.value)-->" }
        case .processingInstruction:
            output += node.value.isEmpty ? "<?\(node.name?.description ?? "")?>" : "<?\(node.name?.description ?? "") \(node.value)?>"
        case .element, .document, .doctype, .entityReference, .namespace:
            break
        }
    }

    /// The namespaces a selected element renders: in inclusive mode every in-scope
    /// binding not yet rendered (so an exposed element re-declares its inherited
    /// context); in exclusive mode only those it visibly uses.
    private func selectedNamespaces(
        _ element: PureXML.Model.Element,
        inScope: [String: String],
        attributes: [PureXML.Model.Attribute],
        rendered: [String: String],
    ) -> [(String, String)] {
        switch options.mode {
        case .inclusive:
            inScope.filter { rendered[$0.key] != $0.value }.map { ($0.key, $0.value) }
        case .exclusive:
            exclusiveNamespaces(element, inScope: inScope, attributes: attributes, rendered: rendered)
        }
    }
}

public extension PureXML.Canonical {
    /// Canonicalizes a node with the given options.
    static func canonicalize(_ node: PureXML.Model.Node, options: Options = .inclusive) -> String {
        Canonicalizer(options: options).canonicalize(node)
    }
}
