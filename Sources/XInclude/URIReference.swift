extension PureXML.XInclude {
    /// A parsed URI reference (scheme, authority, path, query, fragment) and the
    /// RFC 3986 reference-resolution algorithm. No I/O: it only manipulates the
    /// identifier strings so a relative `href` can be resolved against a base.
    struct URIReference: Equatable {
        var scheme: String?
        var authority: String?
        var path: String
        var query: String?
        var fragment: String?

        /// Resolves `reference` against `base`, returning the resolved URI string.
        static func resolve(_ reference: String, against base: String) -> String {
            let ref = parse(reference)
            let baseRef = parse(base)
            return ref.resolved(against: baseRef).recomposed()
        }

        /// The RFC 3986 §5.2.2 transform.
        func resolved(against base: URIReference) -> URIReference {
            if scheme != nil {
                return URIReference(
                    scheme: scheme,
                    authority: authority,
                    path: Self.removeDotSegments(path),
                    query: query,
                    fragment: fragment,
                )
            }
            var result = URIReference(scheme: base.scheme, authority: nil, path: "", query: nil, fragment: fragment)
            if let authority {
                result.authority = authority
                result.path = Self.removeDotSegments(path)
                result.query = query
                return result
            }
            result.authority = base.authority
            resolvePath(base: base, into: &result)
            return result
        }

        private func resolvePath(base: URIReference, into result: inout URIReference) {
            if path.isEmpty {
                result.path = base.path
                result.query = query ?? base.query
            } else {
                let merged = path.hasPrefix("/") ? path : Self.merge(base: base, reference: path)
                result.path = Self.removeDotSegments(merged)
                result.query = query
            }
        }

        private static func merge(base: URIReference, reference: String) -> String {
            if base.authority != nil, base.path.isEmpty {
                return "/" + reference
            }
            guard let slash = base.path.lastIndex(of: "/") else { return reference }
            return base.path[...slash] + reference
        }

        /// The RFC 3986 §5.2.4 dot-segment removal.
        static func removeDotSegments(_ path: String) -> String {
            var input = Substring(path)
            var output = ""
            while !input.isEmpty {
                if input.hasPrefix("../") { input = input.dropFirst(3) } else if input.hasPrefix("./") {
                    input = input.dropFirst(2)
                } else if input.hasPrefix("/./") { input = "/" + input.dropFirst(3) } else if input == "/." {
                    input = "/"
                } else if input.hasPrefix("/../") {
                    input = "/" + input.dropFirst(4)
                    dropLastSegment(&output)
                } else if input == "/.." {
                    input = "/"
                    dropLastSegment(&output)
                } else if input == "." || input == ".." {
                    input = ""
                } else {
                    moveSegment(&input, &output)
                }
            }
            return output
        }

        private static func dropLastSegment(_ output: inout String) {
            if let slash = output.lastIndex(of: "/") {
                output = String(output[..<slash])
            } else {
                output = ""
            }
        }

        private static func moveSegment(_ input: inout Substring, _ output: inout String) {
            var end = input.index(after: input.startIndex)
            while end < input.endIndex, input[end] != "/" {
                end = input.index(after: end)
            }
            output += input[input.startIndex ..< end]
            input = input[end...]
        }

        private func recomposed() -> String {
            var result = ""
            if let scheme { result += scheme + ":" }
            if let authority { result += "//" + authority }
            result += path
            if let query { result += "?" + query }
            if let fragment { result += "#" + fragment }
            return result
        }

        static func parse(_ string: String) -> URIReference {
            var rest = Substring(string)
            var reference = URIReference(scheme: nil, authority: nil, path: "", query: nil, fragment: nil)
            if let hash = rest.firstIndex(of: "#") {
                reference.fragment = String(rest[rest.index(after: hash)...])
                rest = rest[..<hash]
            }
            if let question = rest.firstIndex(of: "?") {
                reference.query = String(rest[rest.index(after: question)...])
                rest = rest[..<question]
            }
            reference.scheme = scanScheme(&rest)
            if rest.hasPrefix("//") {
                rest = rest.dropFirst(2)
                let end = rest.firstIndex { $0 == "/" } ?? rest.endIndex
                reference.authority = String(rest[..<end])
                rest = rest[end...]
            }
            reference.path = String(rest)
            return reference
        }

        private static func scanScheme(_ rest: inout Substring) -> String? {
            guard let colon = rest.firstIndex(of: ":") else { return nil }
            let candidate = rest[..<colon]
            guard let first = candidate.first, first.isLetter,
                  candidate.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }),
                  !candidate.contains("/")
            else {
                return nil
            }
            rest = rest[rest.index(after: colon)...]
            return String(candidate)
        }
    }
}
