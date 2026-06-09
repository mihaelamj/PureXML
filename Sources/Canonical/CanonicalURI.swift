extension PureXML.Canonical.Canonicalizer {
    /// Canonical XML 1.1 inheritance: xml:lang and xml:space inherit nearest;
    /// xml:base is the RFC 3986 resolution of the omitted-ancestor chain folded
    /// with the apex's own; xml:id is not inherited.
    static func inherited11XMLAttributes(above node: PureXML.Model.TreeNode, apex: PureXML.Model.Element, present: Set<String>) -> [PureXML.Model.Attribute] {
        var result: [PureXML.Model.Attribute] = []
        for local in ["lang", "space"] where !present.contains("xml:\(local)") {
            if let attribute = nearestXMLAttribute(local, above: node) { result.append(attribute) }
        }
        if let base = mergedBase(above: node, apex: apex) {
            result.append(PureXML.Model.Attribute("xml:base", base))
        }
        return result
    }

    /// The nearest in-scope `xml:<local>` attribute above a node, or nil.
    private static func nearestXMLAttribute(_ local: String, above node: PureXML.Model.TreeNode) -> PureXML.Model.Attribute? {
        var current = node.parent
        while let ancestor = current {
            if let attribute = ancestor.attributes.first(where: { $0.name.prefix == "xml" && $0.name.localName == local }) {
                return attribute
            }
            current = ancestor.parent
        }
        return nil
    }

    /// The merged `xml:base` for the apex: the omitted-ancestor `xml:base` values
    /// (outermost first) resolved into each other, then the apex's own `xml:base`
    /// resolved against them. Nil when no `xml:base` is in scope.
    private static func mergedBase(above node: PureXML.Model.TreeNode, apex: PureXML.Model.Element) -> String? {
        var nearestFirst: [String] = []
        var current = node.parent
        while let ancestor = current {
            if let attribute = ancestor.attributes.first(where: { $0.name.prefix == "xml" && $0.name.localName == "base" }) {
                nearestFirst.append(attribute.value)
            }
            current = ancestor.parent
        }
        var chain = Array(nearestFirst.reversed())
        if let own = apex.attributes.first(where: { $0.name.prefix == "xml" && $0.name.localName == "base" }) {
            chain.append(own.value)
        }
        guard var merged = chain.first else { return nil }
        for reference in chain.dropFirst() {
            merged = resolveURI(reference, against: merged)
        }
        return merged
    }

    /// Resolves a URI `reference` against a `base` per RFC 3986 section 5
    /// (strict). Used for Canonical XML 1.1 `xml:base` merging, where the
    /// `xml:base` values of omitted ancestors are combined into the apex.
    static func resolveURI(_ reference: String, against base: String) -> String {
        let ref = URIParts(reference)
        if ref.scheme != nil {
            return URIParts(scheme: ref.scheme, authority: ref.authority, path: removeDotSegments(ref.path), query: ref.query, fragment: ref.fragment).recomposed
        }
        let baseParts = URIParts(base)
        var target = URIParts(scheme: baseParts.scheme, authority: nil, path: "", query: nil, fragment: ref.fragment)
        if ref.authority != nil {
            target.authority = ref.authority
            target.path = removeDotSegments(ref.path)
            target.query = ref.query
        } else {
            target.authority = baseParts.authority
            if ref.path.isEmpty {
                target.path = baseParts.path
                target.query = ref.query ?? baseParts.query
            } else if ref.path.hasPrefix("/") {
                target.path = removeDotSegments(ref.path)
                target.query = ref.query
            } else {
                target.path = removeDotSegments(merge(base: baseParts, relativePath: ref.path))
                target.query = ref.query
            }
        }
        return target.recomposed
    }

    /// Merges a relative path onto a base per RFC 3986 section 5.3.
    private static func merge(base: URIParts, relativePath: String) -> String {
        if base.authority != nil, base.path.isEmpty {
            return "/" + relativePath
        }
        if let slash = base.path.lastIndex(of: "/") {
            return String(base.path[...slash]) + relativePath
        }
        return relativePath
    }

    /// Removes `.` and `..` segments per RFC 3986 section 5.2.4.
    private static func removeDotSegments(_ path: String) -> String {
        var input = Substring(path)
        var output = ""
        while !input.isEmpty {
            if input.hasPrefix("../") { input = input.dropFirst(3)
                continue
            }
            if input.hasPrefix("./") { input = input.dropFirst(2)
                continue
            }
            if input.hasPrefix("/./") { input = "/" + input.dropFirst(3)
                continue
            }
            if input == "/." { input = "/"
                continue
            }
            if input.hasPrefix("/../") { input = "/" + input.dropFirst(4)
                removeLastSegment(&output)
                continue
            }
            if input == "/.." { input = "/"
                removeLastSegment(&output)
                continue
            }
            if input == "." || input == ".." { break }
            let start = input.hasPrefix("/") ? input.index(after: input.startIndex) : input.startIndex
            let next = input[start...].firstIndex(of: "/") ?? input.endIndex
            output += input[..<next]
            input = input[next...]
        }
        return output
    }

    private static func removeLastSegment(_ output: inout String) {
        if let slash = output.lastIndex(of: "/") {
            output = String(output[..<slash])
        } else {
            output = ""
        }
    }
}

/// The five components of a URI reference (RFC 3986 section 3).
private struct URIParts {
    var scheme: String?
    var authority: String?
    var path: String
    var query: String?
    var fragment: String?

    init(scheme: String?, authority: String?, path: String, query: String?, fragment: String?) {
        self.scheme = scheme
        self.authority = authority
        self.path = path
        self.query = query
        self.fragment = fragment
    }

    /// Parses a URI reference into its components.
    init(_ text: String) {
        var rest = Substring(text)
        if let hash = rest.firstIndex(of: "#") {
            fragment = String(rest[rest.index(after: hash)...])
            rest = rest[..<hash]
        } else {
            fragment = nil
        }
        if let question = rest.firstIndex(of: "?") {
            query = String(rest[rest.index(after: question)...])
            rest = rest[..<question]
        } else {
            query = nil
        }
        let split = Self.splitScheme(rest)
        scheme = split.scheme
        rest = split.rest
        if rest.hasPrefix("//") {
            let afterSlashes = rest.dropFirst(2)
            let end = afterSlashes.firstIndex(where: { $0 == "/" }) ?? afterSlashes.endIndex
            authority = String(afterSlashes[..<end])
            rest = afterSlashes[end...]
        } else {
            authority = nil
        }
        path = String(rest)
    }

    /// Splits a leading `scheme:` off a reference (scheme present only when a colon
    /// precedes any path separator and the candidate is a valid scheme).
    private static func splitScheme(_ text: Substring) -> (scheme: String?, rest: Substring) {
        guard let colon = text.firstIndex(of: ":") else { return (nil, text) }
        let candidate = text[..<colon]
        let valid = candidate.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
        let startsWithLetter = candidate.first?.isLetter ?? false
        let beforeSlash = text.firstIndex(of: "/").map { colon < $0 } ?? true
        guard valid, startsWithLetter, beforeSlash else { return (nil, text) }
        return (String(candidate), text[text.index(after: colon)...])
    }

    /// Recomposes the components into a URI string (RFC 3986 section 5.3).
    var recomposed: String {
        var result = ""
        if let scheme { result += scheme + ":" }
        if let authority { result += "//" + authority }
        result += path
        if let query { result += "?" + query }
        if let fragment { result += "#" + fragment }
        return result
    }
}
