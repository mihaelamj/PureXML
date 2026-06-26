public extension PureXML.XPointer {
    /// A contiguous range selected by an XPointer range form, materialized as the
    /// whole nodes it spans and the character content it covers. Reimplemented
    /// over the XPointer range model: `range()`, `range-to()`, and `string-range()`.
    struct Range: Sendable, Equatable {
        /// The whole nodes the range spans, in document order.
        public let nodes: [PureXML.Model.Node]
        /// The character content the range covers: the matched substring for a
        /// `string-range`, otherwise the spanned nodes' concatenated text.
        public let text: String
    }

    /// A parsed XPointer range form, awaiting evaluation against a document. The
    /// three forms the XPointer range model defines for selecting between two
    /// points; an ordinary location path is not a range and parses to nil.
    enum RangeForm: Equatable, Sendable {
        /// `range(expr)`: the covering range of each location `expr` selects.
        case covering(expression: String)
        /// `start/range-to(end)`: one range from the first location of `start` to
        /// the first location of `end`.
        case rangeTo(start: String, end: String)
        /// `string-range(location, "search"[, offset[, length]])`: a character
        /// range per occurrence of `search` in each location's string value.
        case stringRange(location: String, search: String, offset: Int?, length: Int?)

        /// Recognizes a range form in `xpointer()` data, or nil when the data is an
        /// ordinary location expression.
        static func parse(_ data: String) -> RangeForm? {
            let trimmed = data.trimmingXMLWhitespace()
            if let inner = inside(trimmed, scheme: "range") {
                return .covering(expression: inner)
            }
            if let inner = inside(trimmed, scheme: "string-range") {
                return stringRange(arguments: inner)
            }
            if let split = rangeToSplit(trimmed) {
                return .rangeTo(start: split.start, end: split.end)
            }
            return nil
        }

        /// The argument inside `scheme( ... )` when `data` is exactly that call.
        private static func inside(_ data: String, scheme: String) -> String? {
            let prefix = scheme + "("
            guard data.hasPrefix(prefix), data.hasSuffix(")") else { return nil }
            let start = data.index(data.startIndex, offsetBy: prefix.count)
            return String(data[start ..< data.index(before: data.endIndex)])
        }

        private static func stringRange(arguments: String) -> RangeForm? {
            let parts = splitTopLevel(arguments, separator: ",").map { $0.trimmingXMLWhitespace() }
            guard parts.count >= 2 else { return nil }
            return .stringRange(
                location: parts[0],
                search: unquote(parts[1]),
                offset: parts.count > 2 ? Int(parts[2]) : nil,
                length: parts.count > 3 ? Int(parts[3]) : nil,
            )
        }

        /// Splits `start/range-to(end)` at the top-level `/range-to(`.
        private static func rangeToSplit(_ data: String) -> (start: String, end: String)? {
            let marker = Array("/range-to(")
            let characters = Array(data)
            var depth = 0
            var quote: Character?
            var index = 0
            while index < characters.count {
                let character = characters[index]
                if let active = quote {
                    if character == active { quote = nil }
                } else if character == "'" || character == "\"" {
                    quote = character
                } else if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth -= 1
                } else if depth == 0, matches(characters, at: index, marker) {
                    let start = String(characters[..<index])
                    let endStart = index + marker.count
                    guard characters.last == ")", endStart < characters.count else { return nil }
                    return (start, String(characters[endStart ..< (characters.count - 1)]))
                }
                index += 1
            }
            return nil
        }

        private static func matches(_ characters: [Character], at index: Int, _ marker: [Character]) -> Bool {
            guard index + marker.count <= characters.count else { return false }
            return Array(characters[index ..< index + marker.count]) == marker
        }

        private static func unquote(_ value: String) -> String {
            guard value.count >= 2, let first = value.first, first == "'" || first == "\"", value.last == first else { return value }
            return String(value.dropFirst().dropLast())
        }

        /// Splits on a separator that is not inside quotes or parentheses.
        private static func splitTopLevel(_ value: String, separator: Character) -> [String] {
            var parts: [String] = []
            var current = ""
            var depth = 0
            var quote: Character?
            for character in value {
                if let active = quote {
                    if character == active { quote = nil }
                    current.append(character)
                } else if character == "'" || character == "\"" {
                    quote = character
                    current.append(character)
                } else if character == "(" || character == "[" {
                    depth += 1
                    current.append(character)
                } else if character == ")" || character == "]" {
                    depth -= 1
                    current.append(character)
                } else if character == separator, depth == 0 {
                    parts.append(current)
                    current = ""
                } else {
                    current.append(character)
                }
            }
            parts.append(current)
            return parts
        }
    }
}

extension PureXML.XPointer.RangeForm {
    /// Evaluates this range form over a pre-built tree, returning the ranges it
    /// selects in document order.
    func ranges(over root: PureXML.Model.TreeNode, namespaces: [String: String]) -> [PureXML.XPointer.Range] {
        switch self {
        case let .covering(expression):
            Self.nodes(expression, over: root, namespaces: namespaces).map { node in
                PureXML.XPointer.Range(nodes: [node.node], text: node.stringValue)
            }
        case let .rangeTo(start, end):
            rangeTo(start: start, end: end, over: root, namespaces: namespaces)
        case let .stringRange(location, search, offset, length):
            Self.stringRanges(in: Self.nodes(location, over: root, namespaces: namespaces), search: search, offset: offset, length: length)
        }
    }

    private func rangeTo(start: String, end: String, over root: PureXML.Model.TreeNode, namespaces: [String: String]) -> [PureXML.XPointer.Range] {
        guard let from = Self.nodes(start, over: root, namespaces: namespaces).first,
              let target = Self.nodes(end, over: root, namespaces: namespaces).first else { return [] }
        let spanned = Self.spannedNodes(from: from, to: target)
        return [PureXML.XPointer.Range(nodes: spanned.map(\.node), text: spanned.map(\.stringValue).joined())]
    }

    private static func stringRanges(in nodes: [PureXML.Model.TreeNode], search: String, offset: Int?, length: Int?) -> [PureXML.XPointer.Range] {
        guard !search.isEmpty else { return [] }
        let needle = Array(search)
        // The needle is the same for every node, so its KMP failure function is
        // built once. The former scan re-tested (and re-allocated) the whole
        // needle window at every position, an O(text * needle) search and a
        // denial-of-service vector on a long node value with a near-matching
        // needle; the search is now O(text + needle).
        let failure = kmpFailure(needle)
        return nodes.flatMap { node -> [PureXML.XPointer.Range] in
            let characters = Array(node.stringValue)
            return nonOverlappingMatches(of: needle, failure: failure, in: characters).map { index in
                let begin = min(index + (offset ?? 1) - 1, characters.count)
                let end = min(begin + (length ?? needle.count), characters.count)
                let text = String(characters[max(begin, 0) ..< max(end, begin)])
                return PureXML.XPointer.Range(nodes: [.text(text)], text: text)
            }
        }
    }

    /// The KMP failure function (for each prefix, the length of its longest
    /// proper prefix that is also a suffix) of `needle`.
    private static func kmpFailure(_ needle: [Character]) -> [Int] {
        var failure = [Int](repeating: 0, count: needle.count)
        var matched = 0
        for index in 1 ..< needle.count {
            while matched > 0, needle[index] != needle[matched] {
                matched = failure[matched - 1]
            }
            if needle[index] == needle[matched] { matched += 1 }
            failure[index] = matched
        }
        return failure
    }

    /// The start indices of `needle` in `haystack`, left to right and
    /// non-overlapping: each match resumes the scan past its end, matching the
    /// former naive scan's `index += needle.count` advance, in O(text + needle).
    private static func nonOverlappingMatches(of needle: [Character], failure: [Int], in haystack: [Character]) -> [Int] {
        var matches: [Int] = []
        var matched = 0
        var index = 0
        while index < haystack.count {
            if haystack[index] == needle[matched] {
                index += 1
                matched += 1
                if matched == needle.count {
                    matches.append(index - needle.count)
                    matched = 0
                }
            } else if matched > 0 {
                matched = failure[matched - 1]
            } else {
                index += 1
            }
        }
        return matches
    }

    /// The whole nodes spanned from `from` to `target`: the sibling run between
    /// them when they share a parent, otherwise the two boundary nodes in document
    /// order.
    private static func spannedNodes(from: PureXML.Model.TreeNode, to target: PureXML.Model.TreeNode) -> [PureXML.Model.TreeNode] {
        let ordered = from.precedes(target) || from === target ? (from, target) : (target, from)
        guard let parent = ordered.0.parent, parent === ordered.1.parent,
              let lower = parent.children.firstIndex(where: { $0 === ordered.0 }),
              let upper = parent.children.firstIndex(where: { $0 === ordered.1 })
        else {
            return ordered.0 === ordered.1 ? [ordered.0] : [ordered.0, ordered.1]
        }
        return Array(parent.children[lower ... upper])
    }

    private static func nodes(_ expression: String, over root: PureXML.Model.TreeNode, namespaces: [String: String]) -> [PureXML.Model.TreeNode] {
        guard let query = try? PureXML.XPath.Query(expression),
              let value = try? query.value(at: root, position: 1, size: 1, variables: [:], namespaces: namespaces) else { return [] }
        return (value.nodes ?? []).compactMap(\.treeNode)
    }
}
