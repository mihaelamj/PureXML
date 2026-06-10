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
        private var pull: () -> Character?
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
        /// The contiguous fast path: when the input is a String, its UTF-8
        /// bytes are copied once into owned storage and scalars decode
        /// straight off the pointer, bypassing the per-character closure
        /// chain entirely.
        private let storage: ByteStorage?
        private var byteIndex = 0

        init(pulling pull: @escaping () -> Character?) {
            storage = nil
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
            // One O(n) copy into owned storage; every scalar after that
            // decodes from the pointer. Each yielded Character is one
            // scalar, the same contract as the streaming path.
            storage = ByteStorage(Array(string.utf8))
            pull = { nil }
        }

        /// Decodes the next scalar from the owned bytes. The input came from
        /// a Swift String, so the UTF-8 is valid by construction; the length
        /// guard is defensive only.
        private mutating func nextFromBytes(_ storage: ByteStorage) -> Character? {
            guard byteIndex < storage.count else { return nil }
            let pointer = storage.pointer
            let first = pointer[byteIndex]
            if first < 0x80 {
                byteIndex += 1
                return Character(Unicode.Scalar(first))
            }
            let length = first >= 0xF0 ? 4 : (first >= 0xE0 ? 3 : 2)
            guard byteIndex + length <= storage.count else {
                byteIndex = storage.count
                return nil
            }
            var value = UInt32(first & (0xFF >> UInt8(length + 1)))
            for index in 1 ..< length {
                value = (value << 6) | UInt32(pointer[byteIndex + index] & 0x3F)
            }
            byteIndex += length
            guard let scalar = Unicode.Scalar(value) else {
                return nil
            }
            return Character(scalar)
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
            if let storage {
                return nextFromBytes(storage)
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
            if buffer.isEmpty, pendingRaw == nil, let storage {
                if let byteResult = matchesBytes(literal, storage) { return byteResult }
            }
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

        /// Byte-level compare for plain ASCII literals without CR or LF
        /// (line-ending normalization cannot touch those, so raw bytes and
        /// the normalized stream agree). Returns nil when the literal needs
        /// the Character path.
        private func matchesBytes(_ literal: String, _ storage: ByteStorage) -> Bool? {
            var index = byteIndex
            for byte in literal.utf8 {
                guard byte < 0x80, byte != 0x0D, byte != 0x0A else { return nil }
                guard index < storage.count, storage.pointer[index] == byte else { return false }
                index += 1
            }
            return true
        }

        /// If the upcoming characters equal `literal`, consume them and return true.
        @discardableResult
        mutating func consume(_ literal: String) -> Bool {
            if buffer.isEmpty, pendingRaw == nil, let storage, let byteResult = matchesBytes(literal, storage) {
                guard byteResult else { return false }
                // ASCII literal without newlines: one byte per scalar, no
                // line changes, so position tracking is plain arithmetic.
                let count = literal.utf8.count
                byteIndex += count
                offset += count
                column += count
                return true
            }
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

        /// Bulk-scans character data in byte mode: consumes and returns the
        /// longest upcoming run of plain ASCII content bytes (no '<', no
        /// carriage return, no "]]" pair, every byte a valid XML character),
        /// or nil when the fast path does not apply. Anything subtle, an
        /// entity boundary aside ('&' is plain content here), is left for
        /// the character path so error marks stay exact. Returns nil rather
        /// than an empty run so callers can alternate with the slow loop.
        mutating func contentRunBytes() -> String? {
            guard buffer.isEmpty, pendingRaw == nil, let storage else { return nil }
            let pointer = storage.pointer
            let count = storage.count
            // A run never contains ']', so "]]>" can only straddle the
            // boundary where the slow path consumed "]]" and the run would
            // begin with '>': leave a leading '>' to the slow path and its
            // cdataCloseInContent check (W3C ibm14n01).
            if byteIndex < count, pointer[byteIndex] == 0x3E { return nil }
            var index = byteIndex
            var newlines = 0
            var lastLineStart = -1
            while index < count {
                let byte = pointer[index]
                if byte == 0x3C { break } // '<'
                // Valid plain ASCII content only; CR, ']' and non-ASCII go
                // to the character path.
                guard byte < 0x80, byte != 0x0D, byte != 0x5D,
                      byte >= 0x20 || byte == 0x09 || byte == 0x0A
                else {
                    if index == byteIndex { return nil }
                    break
                }
                if byte == 0x0A {
                    newlines += 1
                    lastLineStart = index
                }
                index += 1
            }
            guard index > byteIndex else { return nil }
            let run = String(decoding: UnsafeBufferPointer(start: pointer + byteIndex, count: index - byteIndex), as: UTF8.self)
            offset += index - byteIndex
            if newlines > 0 {
                line += newlines
                column = index - lastLineStart
            } else {
                column += index - byteIndex
            }
            byteIndex = index
            return run
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
