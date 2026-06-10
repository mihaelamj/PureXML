/// The full `xsl:number` of XSLT 1.0 section 7.7: `level` single/multiple/any
/// with `count` and `from` patterns, an explicit `value` expression, and the
/// format-token engine (alternating separators and `1`/`01`/`a`/`A`/`i`/`I`
/// tokens, the last token reused, `.` as the default separator).
enum XSLTNumbering {
    typealias Tree = PureXML.Model.TreeNode

    /// The numbers `xsl:number` renders for `node`, computed per level with
    /// `matches` deciding pattern membership (the transformer's match cache).
    static func numbers(
        of node: Tree,
        level: String,
        count: String?,
        from: String?,
        matches: (Tree, String) -> Bool,
    ) -> [Int] {
        func matchesCount(_ candidate: Tree) -> Bool {
            if let count { return matches(candidate, count) }
            return candidate.kind == node.kind && candidate.name?.description == node.name?.description
        }
        func matchesFrom(_ candidate: Tree) -> Bool {
            from.map { matches(candidate, $0) } ?? false
        }
        switch level {
        case "multiple":
            var counts: [Int] = []
            var current: Tree? = node
            while let candidate = current, !matchesFrom(candidate) {
                if matchesCount(candidate) {
                    counts.append(siblingPosition(of: candidate, matching: matchesCount))
                }
                current = candidate.parent
            }
            return counts.reversed()
        case "any":
            var total = 0
            walkPreceding(node) { candidate in
                if matchesFrom(candidate) { return false }
                if matchesCount(candidate) { total += 1 }
                return true
            }
            return [total]
        default: // single
            var current: Tree? = node
            while let candidate = current, !matchesFrom(candidate) {
                if matchesCount(candidate) {
                    return [siblingPosition(of: candidate, matching: matchesCount)]
                }
                current = candidate.parent
            }
            return []
        }
    }

    /// 1 + the count of preceding siblings the count pattern matches.
    private static func siblingPosition(of node: Tree, matching matchesCount: (Tree) -> Bool) -> Int {
        var position = 1
        guard let parent = node.parent else { return position }
        for sibling in parent.children {
            if sibling === node { break }
            if matchesCount(sibling) { position += 1 }
        }
        return position
    }

    /// Visits `node` and everything before it in document order (ancestors
    /// included), nearest first; the visitor returns false to stop.
    private static func walkPreceding(_ node: Tree, _ visit: (Tree) -> Bool) {
        var current: Tree? = node
        while let candidate = current {
            if !visit(candidate) { return }
            var sibling = precedingSibling(of: candidate)
            while let visited = sibling {
                if !visitSubtreeReversed(visited, visit) { return }
                sibling = precedingSibling(of: visited)
            }
            current = candidate.parent
        }
    }

    private static func visitSubtreeReversed(_ node: Tree, _ visit: (Tree) -> Bool) -> Bool {
        for child in node.children.reversed() where !visitSubtreeReversed(child, visit) {
            return false
        }
        return visit(node)
    }

    private static func precedingSibling(of node: Tree) -> Tree? {
        guard let parent = node.parent else { return nil }
        var previous: Tree?
        for sibling in parent.children {
            if sibling === node { return previous }
            previous = sibling
        }
        return nil
    }

    // MARK: Format tokens

    /// Renders `numbers` with the 7.7.1 format engine. An empty list (a
    /// single/multiple level whose count pattern matched nothing) renders as
    /// the empty string, punctuation included.
    static func format(_ numbers: [Int], _ format: String, _ grouping: (separator: String, size: Int)? = nil) -> String {
        guard !numbers.isEmpty else { return "" }
        let pieces = tokenize(format.isEmpty ? "1" : format)
        var result = pieces.prefix
        var lastToken = "1"
        var lastSeparator = "."
        for (offset, number) in numbers.enumerated() {
            if offset > 0 {
                result += offset - 1 < pieces.separators.count ? pieces.separators[offset - 1] : lastSeparator
            }
            let token = offset < pieces.tokens.count ? pieces.tokens[offset] : lastToken
            result += render(number, token, grouping)
            if offset < pieces.tokens.count { lastToken = pieces.tokens[offset] }
            if offset > 0, offset - 1 < pieces.separators.count { lastSeparator = pieces.separators[offset - 1] }
        }
        return result + pieces.suffix
    }

    private struct FormatPieces {
        var prefix = ""
        var tokens: [String] = []
        var separators: [String] = []
        var suffix = ""
    }

    /// Splits a format string into leading punctuation, alternating format
    /// tokens and separators, and trailing punctuation.
    private static func tokenize(_ format: String) -> FormatPieces {
        var pieces = FormatPieces()
        var currentSeparator = ""
        var sawToken = false
        var index = format.startIndex
        while index < format.endIndex {
            if format[index].isLetter || format[index].isNumber {
                var token = ""
                while index < format.endIndex, format[index].isLetter || format[index].isNumber {
                    token.append(format[index])
                    index = format.index(after: index)
                }
                if sawToken {
                    pieces.separators.append(currentSeparator)
                } else {
                    pieces.prefix = currentSeparator
                }
                currentSeparator = ""
                pieces.tokens.append(token)
                sawToken = true
            } else {
                currentSeparator.append(format[index])
                index = format.index(after: index)
            }
        }
        pieces.suffix = currentSeparator
        if !sawToken {
            pieces.prefix = ""
            pieces.suffix = currentSeparator
        }
        return pieces
    }

    /// One number in one token's style.
    static func render(_ number: Int, _ token: String, _ grouping: (separator: String, size: Int)? = nil) -> String {
        switch token.first {
        case "A": return alphabetic(number, base: 65, letters: 26)
        case "a": return alphabetic(number, base: 97, letters: 26)
        case "I": return roman(number).uppercased()
        case "i": return roman(number)
        case "\u{3B1}": return alphabetic(number, base: 0x3B1, letters: 25)
        default:
            var digits = String(number)
            let width = token.count
            if digits.count < width { digits = String(repeating: "0", count: width - digits.count) + digits }
            return grouped(digits, grouping)
        }
    }

    /// Digit grouping per `grouping-separator`/`grouping-size`, applied from
    /// the right.
    private static func grouped(_ digits: String, _ grouping: (separator: String, size: Int)?) -> String {
        guard let grouping, grouping.size > 0, digits.count > grouping.size else { return digits }
        var groups: [String] = []
        var rest = digits[...]
        while rest.count > grouping.size {
            groups.append(String(rest.suffix(grouping.size)))
            rest = rest.dropLast(grouping.size)
        }
        groups.append(String(rest))
        return groups.reversed().joined(separator: grouping.separator)
    }

    private static func alphabetic(_ number: Int, base: UInt32, letters: Int) -> String {
        var value = number
        var result = ""
        while value > 0 {
            let remainder = UInt32((value - 1) % letters)
            if let scalar = Unicode.Scalar(base + remainder) {
                result = String(Character(scalar)) + result
            }
            value = (value - 1) / letters
        }
        return result
    }

    private static func roman(_ number: Int) -> String {
        let table: [(Int, String)] = [
            (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
            (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i"),
        ]
        var value = number
        var result = ""
        for (amount, numeral) in table {
            while value >= amount {
                result += numeral
                value -= amount
            }
        }
        return result
    }
}
