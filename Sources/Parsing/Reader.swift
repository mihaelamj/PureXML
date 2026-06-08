extension PureXML.Parsing {
    /// A streaming character cursor. It pulls characters from a source closure
    /// one at a time, keeping only a small lookahead buffer, so it never holds
    /// the whole input in memory. Tracks line, column, and offset for
    /// diagnostics. Internal to the parser; not part of the API.
    struct Reader {
        private let pull: () -> Character?
        private var buffer: [Character] = []
        private var exhausted = false
        private(set) var offset = 0
        private(set) var line = 1
        private(set) var column = 1

        init(pulling pull: @escaping () -> Character?) {
            self.pull = pull
        }

        init(_ string: String) {
            var iterator = string.makeIterator()
            self.init(pulling: { iterator.next() })
        }

        /// Ensures the lookahead buffer holds at least `count` characters (or the
        /// source is exhausted). The buffer stays bounded by the largest lookahead
        /// any single scan needs, never by the document size.
        private mutating func ensure(_ count: Int) {
            while buffer.count < count, !exhausted {
                if let character = pull() {
                    buffer.append(character)
                } else {
                    exhausted = true
                }
            }
        }

        mutating func peek(_ ahead: Int = 0) -> Character? {
            ensure(ahead + 1)
            return ahead < buffer.count ? buffer[ahead] : nil
        }

        var mark: Mark {
            Mark(line: line, column: column, offset: offset)
        }

        @discardableResult
        mutating func advance() -> Character? {
            ensure(1)
            guard !buffer.isEmpty else { return nil }
            let character = buffer.removeFirst()
            offset += 1
            if character == "\n" {
                line += 1
                column = 1
            } else {
                column += 1
            }
            return character
        }

        /// True if the upcoming characters equal `literal`, without consuming.
        mutating func matches(_ literal: String) -> Bool {
            let target = Array(literal)
            ensure(target.count)
            guard buffer.count >= target.count else { return false }
            for index in target.indices where buffer[index] != target[index] {
                return false
            }
            return true
        }

        /// If the upcoming characters equal `literal`, consume them and return true.
        @discardableResult
        mutating func consume(_ literal: String) -> Bool {
            guard matches(literal) else { return false }
            for _ in literal {
                advance()
            }
            return true
        }

        mutating func skipSpace() {
            while let character = peek(), character.isXMLWhitespace {
                advance()
            }
        }
    }
}

extension StringProtocol {
    /// Trims leading and trailing XML whitespace without Foundation.
    func trimmingXMLWhitespace() -> String {
        var slice = self[...]
        while let first = slice.first, first.isXMLWhitespace {
            slice = slice.dropFirst()
        }
        while let last = slice.last, last.isXMLWhitespace {
            slice = slice.dropLast()
        }
        return String(slice)
    }
}

extension Character {
    private typealias XML = PureXML.Parsing.XMLCharacter

    /// XML S production: space, tab, carriage return, line feed.
    var isXMLWhitespace: Bool {
        unicodeScalars.count == 1 && unicodeScalars.first.map(XML.isWhitespace) == true
    }

    /// Whether this character may start an XML name. A grapheme qualifies when its
    /// first scalar is a NameStartChar and any trailing scalars (combining marks)
    /// are NameChar.
    var isXMLNameStart: Bool {
        guard let first = unicodeScalars.first, XML.isNameStart(first) else { return false }
        return unicodeScalars.dropFirst().allSatisfy(XML.isNameChar)
    }

    /// Whether this character may continue an XML name (every scalar a NameChar).
    var isXMLNameContinuation: Bool {
        !unicodeScalars.isEmpty && unicodeScalars.allSatisfy(XML.isNameChar)
    }
}
