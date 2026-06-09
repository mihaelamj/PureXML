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
                for child in children {
                    emit(child, inScope: inScope, rendered: rendered, output: &output)
                }
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
            for child in element.children {
                emit(child, inScope: childInScope, rendered: childRendered, output: &output)
            }
            output += "</\(element.name.description)>"
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
                declarations.filter { rendered[$0.0] != $0.1 }
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

        // MARK: Node-subset context

        /// The apex element with its inherited `xml:*` attributes added, and (for
        /// inclusive mode) the namespaces in scope from omitted ancestors merged in
        /// as declarations so the apex renders its full namespace context.
        private static func augmentedApex(
            _ apex: PureXML.Model.Element,
            inheritedXML: [PureXML.Model.Attribute],
            mergingNamespaces ancestorNamespaces: [String: String]?,
            stripApexBase: Bool,
        ) -> PureXML.Model.Element {
            // Under 1.1, the apex's own xml:base is folded into the merged base in
            // inheritedXML, so drop the original to avoid emitting it twice.
            let own = stripApexBase
                ? apex.attributes.filter { !($0.name.prefix == "xml" && $0.name.localName == "base") }
                : apex.attributes
            var attributes = own + inheritedXML
            if let ancestorNamespaces {
                let declared = Set(apex.attributes.map(\.name.description))
                for (prefix, uri) in ancestorNamespaces {
                    let name = prefix.isEmpty ? "xmlns" : "xmlns:\(prefix)"
                    if !declared.contains(name) { attributes.append(PureXML.Model.Attribute(name, uri)) }
                }
            }
            return PureXML.Model.Element(name: apex.name, attributes: attributes, children: apex.children)
        }

        /// The namespace declarations in scope from a node's omitted ancestors,
        /// nearest ancestor winning (so an inner redeclaration is preserved).
        private static func inScopeNamespaces(above node: PureXML.Model.TreeNode) -> [String: String] {
            var result: [String: String] = [:]
            var current = node.parent
            while let ancestor = current {
                for attribute in ancestor.attributes {
                    guard let prefix = declaredPrefix(of: attribute.name), result[prefix] == nil else { continue }
                    result[prefix] = attribute.value
                }
                current = ancestor.parent
            }
            return result
        }

        /// The `xml:*` attributes in scope from a node's omitted ancestors that the
        /// apex does not already set, nearest ancestor winning.
        private static func inheritedXMLAttributes(above node: PureXML.Model.TreeNode, apex: PureXML.Model.Element, mergeBase: Bool) -> [PureXML.Model.Attribute] {
            let present = Set(apex.attributes.map(\.name.description))
            if mergeBase { return inherited11XMLAttributes(above: node, apex: apex, present: present) }
            // Canonical XML 1.0: the nearest of every in-scope xml:* attribute the
            // apex does not already set.
            var seen: Set<String> = []
            var result: [PureXML.Model.Attribute] = []
            var current = node.parent
            while let ancestor = current {
                for attribute in ancestor.attributes where attribute.name.prefix == "xml" {
                    let key = attribute.name.description
                    guard !present.contains(key), seen.insert(key).inserted else { continue }
                    result.append(attribute)
                }
                current = ancestor.parent
            }
            return result
        }

        /// The prefix a namespace declaration binds (empty for the default
        /// namespace), or nil when the attribute is not a namespace declaration.
        private static func declaredPrefix(of name: PureXML.Model.QualifiedName) -> String? {
            if name.prefix == nil, name.localName == "xmlns" { return "" }
            if name.prefix == "xmlns" { return name.localName }
            return nil
        }

        // MARK: Escaping

        private static func escapeText(_ value: String) -> String {
            var result = ""
            for character in value {
                switch character {
                case "&": result += "&amp;"
                case "<": result += "&lt;"
                case ">": result += "&gt;"
                case "\r": result += "&#xD;"
                default: result.append(character)
                }
            }
            return result
        }

        private static func escapeAttribute(_ value: String) -> String {
            var result = ""
            for character in value {
                switch character {
                case "&": result += "&amp;"
                case "<": result += "&lt;"
                case "\"": result += "&quot;"
                case "\t": result += "&#x9;"
                case "\n": result += "&#xA;"
                case "\r": result += "&#xD;"
                default: result.append(character)
                }
            }
            return result
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
        _ node: PureXML.Model.TreeNode,
        inScope: [String: String],
        rendered: [String: String],
        including predicate: (PureXML.Model.TreeNode) -> Bool,
        output: inout String,
    ) {
        switch node.kind {
        case .document:
            for child in node.children {
                emitSelected(child, inScope: inScope, rendered: rendered, including: predicate, output: &output)
            }
        case .element:
            emitSelected(element: node, inScope: inScope, rendered: rendered, including: predicate, output: &output)
        case .text, .cdata:
            if predicate(node) { output += Self.escapeText(options.trimTextNodes ? node.value.trimmingXMLWhitespace() : node.value) }
        case .comment:
            if predicate(node), options.includeComments { output += "<!--\(node.value)-->" }
        case .processingInstruction:
            if predicate(node) { output += node.value.isEmpty ? "<?\(node.name?.description ?? "")?>" : "<?\(node.name?.description ?? "") \(node.value)?>" }
        case .doctype, .entityReference, .namespace:
            break
        }
    }

    private func emitSelected(
        element node: PureXML.Model.TreeNode,
        inScope: [String: String],
        rendered: [String: String],
        including predicate: (PureXML.Model.TreeNode) -> Bool,
        output: inout String,
    ) {
        let element = PureXML.Model.Element(name: node.name ?? .init(""), attributes: node.attributes, children: [])
        var childInScope = inScope
        for (prefix, uri) in Self.namespaceDeclarations(element) {
            childInScope[prefix] = uri
        }
        guard predicate(node) else {
            // Omitted element: its namespaces stay in scope for descendants, but
            // nothing is rendered, so a selected descendant renders them itself.
            for child in node.children {
                emitSelected(child, inScope: childInScope, rendered: rendered, including: predicate, output: &output)
            }
            return
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
        for child in node.children {
            emitSelected(child, inScope: childInScope, rendered: childRendered, including: predicate, output: &output)
        }
        output += "</\(element.name.description)>"
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
