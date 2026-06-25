extension PureXML.XPath {
    /// The XPath 1.0 string functions: `concat`, `starts-with`, `contains`,
    /// `substring-before`, `substring-after`, `substring`, `string-length`,
    /// `normalize-space`, and `translate`.
    enum StringFunctions {
        nonisolated(unsafe) static let table = FunctionTable([
            "concat": { arguments, _ in .string(arguments.map(\.string).joined()) },
            "starts-with": { arguments, _ in
                .boolean(argument(arguments, 0).hasPrefix(argument(arguments, 1)))
            },
            "contains": { arguments, _ in
                .boolean(search(Array(argument(arguments, 1)), in: Array(argument(arguments, 0))) != nil)
            },
            "substring-before": { arguments, _ in .string(substringBefore(arguments)) },
            "substring-after": { arguments, _ in .string(substringAfter(arguments)) },
            "substring": { arguments, _ in .string(substring(arguments)) },
            "string-length": { arguments, context in
                .number(Double(stringOrContext(arguments, context).count))
            },
            "normalize-space": { arguments, context in
                .string(normalizeSpace(stringOrContext(arguments, context)))
            },
            "translate": { arguments, _ in .string(translate(arguments)) },
        ])

        private static func argument(_ arguments: [Value], _ index: Int) -> String {
            index < arguments.count ? arguments[index].string : ""
        }

        private static func stringOrContext(_ arguments: [Value], _ context: EvaluationContext) -> String {
            arguments.first?.string ?? context.node.stringValue
        }

        private static func substringBefore(_ arguments: [Value]) -> String {
            let haystack = Array(argument(arguments, 0))
            let needle = Array(argument(arguments, 1))
            guard !needle.isEmpty, let start = search(needle, in: haystack) else { return "" }
            return String(haystack[..<start])
        }

        private static func substringAfter(_ arguments: [Value]) -> String {
            let haystack = Array(argument(arguments, 0))
            let needle = Array(argument(arguments, 1))
            // XPath errata E22: substring-after(s, "") is s. The empty string
            // matches at the start (search returns 0), so everything after it is
            // the whole string; a non-empty needle that is absent still yields "".
            guard let start = search(needle, in: haystack) else { return "" }
            return String(haystack[(start + needle.count)...])
        }

        /// The index of the first occurrence of `needle` in `haystack`, or nil.
        /// Linear-time (Knuth-Morris-Pratt): matching `needle` at every position
        /// of `haystack` is O(n*m) and quadratic on a repetitive string (a denial
        /// of service vector on untrusted input); KMP never rescans, so it is
        /// O(n+m).
        private static func search(_ needle: [Character], in haystack: [Character]) -> Int? {
            guard !needle.isEmpty else { return 0 }
            guard needle.count <= haystack.count else { return nil }
            // The failure function: failure[i] is the length of the longest
            // proper prefix of needle[0...i] that is also a suffix of it.
            var failure = [Int](repeating: 0, count: needle.count)
            var prefix = 0
            for index in 1 ..< needle.count {
                while prefix > 0, needle[index] != needle[prefix] {
                    prefix = failure[prefix - 1]
                }
                if needle[index] == needle[prefix] { prefix += 1 }
                failure[index] = prefix
            }
            var matched = 0
            for index in haystack.indices {
                while matched > 0, haystack[index] != needle[matched] {
                    matched = failure[matched - 1]
                }
                if haystack[index] == needle[matched] { matched += 1 }
                if matched == needle.count { return index - needle.count + 1 }
            }
            return nil
        }

        private static func substring(_ arguments: [Value]) -> String {
            let characters = Array(argument(arguments, 0))
            let from = arguments.count > 1 ? rounded(arguments[1].number) : 1
            let limit: Double = arguments.count > 2 ? from + rounded(arguments[2].number) : .infinity
            var result = ""
            for (offset, character) in characters.enumerated() {
                let position = Double(offset + 1)
                if position >= from, position < limit {
                    result.append(character)
                }
            }
            return result
        }

        private static func normalizeSpace(_ value: String) -> String {
            value.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
                .joined(separator: " ")
        }

        private static func translate(_ arguments: [Value]) -> String {
            let source = argument(arguments, 0)
            let from = Array(argument(arguments, 1))
            let replacements = Array(argument(arguments, 2))
            // Build the translation map once: a from-character maps to its
            // replacement, or is marked for deletion when it has no positional
            // replacement. The first occurrence in `from` wins (the XPath rule).
            // Each source character is then translated by an O(1) lookup rather
            // than a linear scan of `from`, which made this quadratic.
            var replace: [Character: Character] = [:]
            var delete: Set<Character> = []
            for (index, character) in from.enumerated() {
                if replace[character] != nil || delete.contains(character) { continue }
                if index < replacements.count {
                    replace[character] = replacements[index]
                } else {
                    delete.insert(character)
                }
            }
            var result = ""
            result.reserveCapacity(source.count)
            for character in source {
                if let replacement = replace[character] {
                    result.append(replacement)
                } else if !delete.contains(character) {
                    result.append(character)
                }
            }
            return result
        }

        /// XPath rounding: half rounds toward positive infinity, with NaN and
        /// infinities passed through.
        static func rounded(_ value: Double) -> Double {
            if value.isNaN || value.isInfinite { return value }
            return (value + 0.5).rounded(.down)
        }
    }
}
