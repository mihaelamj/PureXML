extension PureXML.Parsing {
    /// A streaming character cursor. It pulls characters from a source closure
    /// one at a time, keeping only a small lookahead buffer, so it never holds
    /// the whole input in memory. Tracks line, column, and offset for
    /// diagnostics. Internal to the parser; not part of the API.
    ///
    /// Lexing is scalar-level: every buffered `Character` holds exactly one
    /// Unicode scalar (multi-scalar graphemes from the source are split), so a
    /// combining mark directly after an ASCII delimiter cannot merge with it
    /// and XML's scalar-defined productions classify correctly. Grapheme
    /// clusters reassemble naturally wherever scanned text is appended to a
    /// `String`.
    struct Reader {
        private let pull: () -> Character?
        private var buffer: [Character] = []
        private var exhausted = false
        private(set) var offset = 0
        private(set) var line = 1
        private(set) var column = 1
        /// When true, also fold the XML 1.1 line terminators NEL (U+0085) and LINE
        /// SEPARATOR (U+2028) to a line feed. Set once the declaration is known to
        /// name version 1.1.
        var xml11 = false
        /// A raw character read past a carriage return that was not part of the
        /// line ending, held back to be returned next.
        private var pendingRaw: Character?

        init(pulling pull: @escaping () -> Character?) {
            // Split multi-scalar graphemes so the buffer is scalar-level.
            var queued: [Character] = []
            self.pull = {
                if !queued.isEmpty { return queued.removeFirst() }
                guard let next = pull() else { return nil }
                let scalars = next.unicodeScalars
                guard scalars.count > 1 else { return next }
                var parts = scalars.map(Character.init)
                let first = parts.removeFirst()
                queued = parts
                return first
            }
        }

        init(_ string: String) {
            // Iterate scalars directly: each yielded Character is one scalar.
            var iterator = string.unicodeScalars.makeIterator()
            self.init(pulling: { iterator.next().map(Character.init) })
        }

        /// Ensures the lookahead buffer holds at least `count` characters (or the
        /// source is exhausted). The buffer stays bounded by the largest lookahead
        /// any single scan needs, never by the document size.
        private mutating func ensure(_ count: Int) {
            while buffer.count < count, !exhausted {
                if let character = normalizedPull() {
                    buffer.append(character)
                } else {
                    exhausted = true
                }
            }
        }

        /// Pulls the next character with XML line-ending normalization: a carriage
        /// return, alone or followed by a line feed (or by NEL in 1.1), becomes a
        /// single line feed, as do a lone NEL and LINE SEPARATOR in 1.1. So every
        /// scan downstream sees line feeds only, as the spec requires.
        private mutating func normalizedPull() -> Character? {
            guard let character = rawNext() else { return nil }
            // Swift coalesces a CR+LF pair into one grapheme-cluster character.
            if character == "\r\n" { return "\n" }
            if character == "\r" {
                let next = rawNext()
                if next != "\n", !(xml11 && next == "\u{85}") { pendingRaw = next }
                return "\n"
            }
            if xml11, character == "\u{85}" || character == "\u{2028}" {
                return "\n"
            }
            return character
        }

        private mutating func rawNext() -> Character? {
            if let pending = pendingRaw {
                pendingRaw = nil
                return pending
            }
            return pull()
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
            // No per-call Array materialization: literals are short constants
            // and this runs on every scan decision (the hottest comparison in
            // the parse profile).
            let count = literal.count
            ensure(count)
            guard buffer.count >= count else { return false }
            var index = 0
            for character in literal {
                if buffer[index] != character { return false }
                index += 1
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

        /// Prepends `text` to the unread stream: used to splice a general
        /// entity's replacement text into content so it is reparsed as markup
        /// (4.4.2 Included). Position tracking keeps reporting the source
        /// document's marks, the libxml2 model for entity boundaries.
        mutating func inject(_ text: String) {
            buffer.insert(contentsOf: text.unicodeScalars.map(Character.init), at: 0)
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
