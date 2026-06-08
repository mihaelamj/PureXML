/// Reads the name and attributes out of a start tag's interior. File-scope and
/// private: an internal detail of ``PureXML/Parsing/PushScanner``.
private struct TagCursor {
    private let chars: [Character]
    private var index = 0

    init(_ chars: [Character]) {
        self.chars = chars
    }

    mutating func readName() -> String {
        skipSpace()
        return readNameToken()
    }

    mutating func readAttribute() -> PureXML.Parsing.PushAttribute? {
        skipSpace()
        let name = readNameToken()
        guard !name.isEmpty else { return nil }
        skipSpace()
        guard peek() == "=" else { return .init(name: name, value: "") }
        advance()
        skipSpace()
        return .init(name: name, value: readValue())
    }

    private mutating func readValue() -> String {
        guard let quote = peek(), quote == "\"" || quote == "'" else { return readUnquoted() }
        advance()
        var value = ""
        while let character = peek(), character != quote {
            value.append(character)
            advance()
        }
        advance()
        return decode(value)
    }

    private mutating func readUnquoted() -> String {
        var value = ""
        while let character = peek(), !character.isXMLWhitespace {
            value.append(character)
            advance()
        }
        return decode(value)
    }

    private mutating func readNameToken() -> String {
        var name = ""
        while let character = peek(), character.isXMLNameContinuation {
            name.append(character)
            advance()
        }
        return name
    }

    private func decode(_ value: String) -> String {
        var budget = Int.max
        return (try? PureXML.Parsing.EntityDecoder.decode(value, entities: [:], budget: &budget, at: .start)) ?? value
    }

    private func peek() -> Character? {
        index < chars.count ? chars[index] : nil
    }

    private mutating func advance() {
        if index < chars.count { index += 1 }
    }

    private mutating func skipSpace() {
        while let character = peek(), character.isXMLWhitespace {
            advance()
        }
    }
}

extension PureXML.Parsing {
    /// One token recognized by the resumable scanner.
    enum PushToken: Equatable, Sendable {
        case open(name: String, attributes: [PushAttribute], selfClosing: Bool)
        case close(name: String)
        case text(String)
        case comment(String)
        case cdata(String)
        case processingInstruction(target: String, data: String)
        /// An ignorable construct (XML declaration or doctype).
        case ignorable
    }

    /// A raw start-tag attribute (name and value, before namespace resolution).
    struct PushAttribute: Equatable, Sendable {
        var name: String
        var value: String
    }

    /// The outcome of one resumable scan.
    enum Scanned: Equatable, Sendable {
        /// A complete token and the number of leading characters it consumed.
        case token(PushToken, consumed: Int)
        /// The buffer ends mid-token; feed more input and scan again from the
        /// same position (the Expat `XML_TOK_PARTIAL` model).
        case needMore
    }

    /// A resumable XML tokenizer. It only reports a token once that token's
    /// terminator is fully present in the buffer; otherwise it returns
    /// ``Scanned/needMore`` and leaves the buffer untouched so the caller can feed
    /// more input and rescan. The only retained state across feeds is the
    /// unconsumed buffer, which is bounded by the largest single token.
    enum PushScanner {
        static func scan(_ buffer: [Character], final: Bool) -> Scanned {
            guard let first = buffer.first else { return .needMore }
            return first == "<" ? scanMarkup(buffer, final: final) : scanText(buffer, final: final)
        }

        // MARK: Text

        private static func scanText(_ buffer: [Character], final: Bool) -> Scanned {
            if let lessThan = buffer.firstIndex(of: "<") {
                return lessThan == 0 ? scanMarkup(buffer, final: final)
                    : .token(.text(decode(buffer[0 ..< lessThan])), consumed: lessThan)
            }
            // No markup ahead: a text run is complete only at the end of input,
            // so an entity reference is never split across a feed.
            return final ? .token(.text(decode(buffer[...])), consumed: buffer.count) : .needMore
        }

        // MARK: Markup

        private static func scanMarkup(_ buffer: [Character], final: Bool) -> Scanned {
            if isPrefix(buffer, ofAny: ["<!--", "<![CDATA[", "<!", "</", "<?"], decidedAt: 2), !final {
                return .needMore
            }
            if startsWith(buffer, "<!--") { return delimited(buffer, open: 4, close: "-->") { .comment(String($0)) } }
            if startsWith(buffer, "<![CDATA[") { return delimited(buffer, open: 9, close: "]]>") { .cdata(String($0)) } }
            if startsWith(buffer, "<!") { return until(buffer, terminator: ">") { _ in .ignorable } }
            if startsWith(buffer, "</") { return scanEndTag(buffer) }
            if startsWith(buffer, "<?") { return scanProcessingInstruction(buffer) }
            return scanStartTag(buffer, final: final)
        }

        private static func scanEndTag(_ buffer: [Character]) -> Scanned {
            until(buffer, terminator: ">") { inner in
                .close(name: String(inner.drop { $0 == "/" }).trimmingXMLWhitespace())
            }
        }

        private static func scanProcessingInstruction(_ buffer: [Character]) -> Scanned {
            delimited(buffer, open: 2, close: "?>") { inner in
                let text = String(inner)
                guard let space = text.firstIndex(where: \.isXMLWhitespace) else {
                    return .processingInstruction(target: text, data: "")
                }
                return .processingInstruction(
                    target: String(text[..<space]),
                    data: String(text[text.index(after: space)...]).trimmingXMLWhitespace(),
                )
            }
        }

        private static func scanStartTag(_ buffer: [Character], final: Bool) -> Scanned {
            guard let end = tagEnd(buffer) else { return final ? .token(.text("<"), consumed: 1) : .needMore }
            var inner = Array(buffer[1 ..< end])
            let selfClosing = inner.last == "/"
            if selfClosing { inner.removeLast() }
            let (name, attributes) = parseTag(inner)
            return .token(.open(name: name, attributes: attributes, selfClosing: selfClosing), consumed: end + 1)
        }

        // MARK: Terminator scanning

        private static func delimited(
            _ buffer: [Character],
            open: Int,
            close: String,
            _ make: (ArraySlice<Character>) -> PushToken,
        ) -> Scanned {
            let target = Array(close)
            var index = open
            while index + target.count <= buffer.count {
                if Array(buffer[index ..< index + target.count]) == target {
                    return .token(make(buffer[open ..< index]), consumed: index + target.count)
                }
                index += 1
            }
            return .needMore
        }

        private static func until(
            _ buffer: [Character],
            terminator: Character,
            _ make: (ArraySlice<Character>) -> PushToken,
        ) -> Scanned {
            guard let end = buffer.firstIndex(of: terminator) else { return .needMore }
            return .token(make(buffer[2 ..< end]), consumed: end + 1)
        }

        /// The index of the `>` that closes a start tag, skipping any inside quotes.
        private static func tagEnd(_ buffer: [Character]) -> Int? {
            var quote: Character?
            for index in 1 ..< buffer.count {
                let character = buffer[index]
                if let active = quote {
                    if character == active { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == ">" {
                    return index
                }
            }
            return nil
        }

        // MARK: Tag and entity parsing

        private static func parseTag(_ inner: [Character]) -> (name: String, attributes: [PushAttribute]) {
            var cursor = TagCursor(inner)
            let name = cursor.readName()
            var attributes: [PushAttribute] = []
            while let attribute = cursor.readAttribute() {
                attributes.append(attribute)
            }
            return (name, attributes)
        }

        private static func decode(_ slice: ArraySlice<Character>) -> String {
            var budget = Int.max
            return (try? EntityDecoder.decode(String(slice), entities: [:], budget: &budget, at: .start)) ?? String(slice)
        }

        private static func startsWith(_ buffer: [Character], _ prefix: String) -> Bool {
            let target = Array(prefix)
            guard buffer.count >= target.count else { return false }
            return Array(buffer[0 ..< target.count]) == target
        }

        /// Whether the buffer is too short to decide which markup kind it is.
        private static func isPrefix(_ buffer: [Character], ofAny _: [String], decidedAt: Int) -> Bool {
            buffer.count < decidedAt
        }
    }
}
