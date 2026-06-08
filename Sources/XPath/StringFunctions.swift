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
            guard !needle.isEmpty, let start = search(needle, in: haystack) else { return "" }
            return String(haystack[(start + needle.count)...])
        }

        /// The index of the first occurrence of `needle` in `haystack`, or nil.
        private static func search(_ needle: [Character], in haystack: [Character]) -> Int? {
            guard !needle.isEmpty else { return 0 }
            for start in haystack.indices where haystack[start...].starts(with: needle) {
                return start
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
            var result = ""
            for character in source {
                guard let index = from.firstIndex(of: character) else {
                    result.append(character)
                    continue
                }
                if index < replacements.count {
                    result.append(replacements[index])
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
