typealias RNGTree = PureXML.Model.TreeNode

/// RNGTree helpers for the RELAX NG parser. File-scope and private.
enum RNGNode {
    static func localName(_ node: RNGTree) -> String? {
        node.name?.localName
    }

    static func attribute(_ node: RNGTree, _ name: String) -> String? {
        let raw = node.attributes.first { $0.name.localName == name }?.value
        // Simplification 4.2: the value of name, type, and combine attributes
        // is whitespace-trimmed.
        guard let raw, ["name", "type", "combine"].contains(name) else { return raw }
        return raw.trimmingXMLWhitespace()
    }

    /// The RELAX NG namespace; simplification 4.1 removes foreign-namespace
    /// elements (annotations such as documentation or comments) before any
    /// pattern interpretation.
    static let relaxNGNamespace = "http://relaxng.org/ns/structure/1.0"

    static func elementChildren(_ node: RNGTree) -> [RNGTree] {
        node.children.filter { child in
            guard child.kind == .element else { return false }
            // Simplification 4.1: only RELAX NG-namespace elements are schema
            // content. An element with no namespace counts as schema content
            // only when the whole document is unqualified (leniency for
            // namespace-less schemas); under a qualified parent it is foreign.
            let uri = child.name?.namespaceURI
            if uri == relaxNGNamespace { return true }
            return uri == nil && node.name?.namespaceURI == nil
        }
    }

    static func children(_ node: RNGTree, named name: String) -> [RNGTree] {
        elementChildren(node).filter { localName($0) == name }
    }

    static func text(_ node: RNGTree) -> String {
        node.stringValue.trimmingXMLWhitespace()
    }

    static func strip(_ qualified: String) -> String {
        qualified.split(separator: ":").last.map(String.init) ?? qualified
    }

    /// The nearest `ns` attribute on the node or an ancestor (simplification
    /// 4.9 inheritance), or nil when none is in scope in this document.
    static func inheritedNS(_ node: RNGTree) -> String? {
        var current: RNGTree? = node
        while let candidate = current {
            if let namespace = candidate.attributes.first(where: { $0.name.prefix == nil && $0.name.localName == "ns" })?.value {
                return namespace
            }
            current = candidate.parent
        }
        return nil
    }

    /// Resolves a prefixed name against the xmlns declarations in scope at the
    /// schema node (simplification 4.10), or nil for an unprefixed name.
    static func resolveQName(_ raw: String, at node: RNGTree) -> (namespace: String, localName: String)? {
        guard let colon = raw.firstIndex(of: ":") else { return nil }
        let prefix = String(raw[..<colon])
        let local = String(raw[raw.index(after: colon)...])
        if prefix == "xml" { return ("http://www.w3.org/XML/1998/namespace", local) }
        var current: RNGTree? = node
        while let candidate = current {
            if let uri = candidate.attributes.first(where: { $0.name.prefix == "xmlns" && $0.name.localName == prefix })?.value {
                return (uri, local)
            }
            current = candidate.parent
        }
        return nil
    }

    /// Resolves `reference` against an optional base URI (RFC 3986), keeping a
    /// relative base's merged form relative (the same adjustment external
    /// identifiers use).
    static func resolveRelative(_ reference: String, against base: String?) -> String {
        guard let base, !base.isEmpty else { return reference }
        let merged = PureXML.Canonical.Canonicalizer.resolveURI(reference, against: base)
        let baseHasScheme = base.split(separator: "/", maxSplits: 1)[0].hasSuffix(":")
        if !base.hasPrefix("/"), !baseHasScheme, !reference.hasPrefix("/"), merged.hasPrefix("/") {
            return String(merged.dropFirst())
        }
        return merged
    }

    /// The `href` of an include/externalRef, resolved against the document's
    /// base and the `xml:base` attributes in scope at the node (4.5).
    static func resolvedHref(_ node: RNGTree, documentBase: String?) -> String? {
        guard let href = attribute(node, "href") else { return nil }
        var bases: [String] = []
        var cursor: RNGTree? = node
        while let current = cursor {
            if let base = current.attributes.first(where: { $0.name.prefix == "xml" && $0.name.localName == "base" })?.value {
                bases.append(base)
            }
            cursor = current.parent
        }
        if let documentBase { bases.append(documentBase) }
        var resolved = href
        for base in bases {
            resolved = resolveRelative(resolved, against: base)
        }
        return resolved
    }
}
