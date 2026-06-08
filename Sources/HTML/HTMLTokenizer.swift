extension PureXML.HTML {
    /// A lenient HTML tokenizer for tag-soup input: case-insensitive tag names,
    /// quoted/unquoted/boolean attributes, comments, doctype, and raw-text
    /// elements (`script`, `style`, `textarea`, `title`) whose content is taken
    /// verbatim. Malformed markup degrades to text rather than failing.
    struct Tokenizer {
        private let chars: [Character]
        private var index = 0
        private var rawTextName: String?

        init(_ html: String) {
            chars = Array(html)
        }

        mutating func tokenize() -> [Token] {
            var tokens: [Token] = []
            while let token = next() {
                tokens.append(token)
            }
            return tokens
        }

        private mutating func next() -> Token? {
            guard !isAtEnd else { return nil }
            if let raw = rawTextName {
                rawTextName = nil
                return rawText(until: raw)
            }
            guard peek() == "<" else { return text() }
            if matches("<!--") { return comment() }
            if matches("<!") { return doctype() }
            if matches("</") { return endTag() }
            if peek(1)?.isLetter == true { return startTag() }
            return text()
        }

        // MARK: Tokens

        private mutating func text() -> Token {
            var value = ""
            if let first = advance() { value.append(first) }
            while let character = peek(), character != "<" {
                value.append(character)
                advance()
            }
            return .text(Self.decodeEntities(value))
        }

        private mutating func startTag() -> Token {
            advance()
            let name = readName().lowercased()
            var attributes: [(String, String)] = []
            var selfClosing = false
            while !isAtEnd {
                skipSpace()
                if consume("/>") { selfClosing = true
                    break
                }
                if consume(">") { break }
                guard let attribute = readAttribute() else { advance()
                    continue
                }
                attributes.append(attribute)
            }
            if Elements.rawText.contains(name) { rawTextName = name }
            return .startTag(name: name, attributes: attributes, selfClosing: selfClosing)
        }

        private mutating func readAttribute() -> (String, String)? {
            let name = readAttributeName().lowercased()
            guard !name.isEmpty else { return nil }
            skipSpace()
            guard consume("=") else { return (name, "") }
            skipSpace()
            return (name, readAttributeValue())
        }

        private mutating func readAttributeValue() -> String {
            guard let quote = peek(), quote == "\"" || quote == "'" else {
                var value = ""
                while let character = peek(), !character.isWhitespace, character != ">" {
                    value.append(character)
                    advance()
                }
                return Self.decodeEntities(value)
            }
            advance()
            var value = ""
            while let character = peek(), character != quote {
                value.append(character)
                advance()
            }
            consume(String(quote))
            return Self.decodeEntities(value)
        }

        private mutating func endTag() -> Token {
            advance()
            advance()
            let name = readName().lowercased()
            skipUntil(">")
            return .endTag(name: name)
        }

        private mutating func comment() -> Token {
            index += 4
            var value = ""
            while !isAtEnd, !matches("-->") {
                value.append(chars[index])
                index += 1
            }
            _ = consume("-->")
            return .comment(value)
        }

        private mutating func doctype() -> Token {
            index += 2
            var value = ""
            while let character = peek(), character != ">" {
                value.append(character)
                advance()
            }
            consume(">")
            return .doctype(value)
        }

        private mutating func rawText(until name: String) -> Token {
            let target = Array("</" + name)
            var value = ""
            while !isAtEnd, !matchesCaseInsensitive(target) {
                value.append(chars[index])
                index += 1
            }
            return .text(value)
        }

        // MARK: Cursor

        private mutating func readName() -> String {
            var name = ""
            while let character = peek(), character.isLetter || character.isNumber || character == "-" {
                name.append(character)
                advance()
            }
            return name
        }

        private mutating func readAttributeName() -> String {
            var name = ""
            while let character = peek(), Self.isAttributeNameCharacter(character) {
                name.append(character)
                advance()
            }
            return name
        }

        private static func isAttributeNameCharacter(_ character: Character) -> Bool {
            !character.isWhitespace && character != "=" && character != ">" && character != "/"
        }

        private var isAtEnd: Bool {
            index >= chars.count
        }

        private func peek(_ ahead: Int = 0) -> Character? {
            let target = index + ahead
            return target < chars.count ? chars[target] : nil
        }

        private func matches(_ literal: String) -> Bool {
            let target = Array(literal)
            guard index + target.count <= chars.count else { return false }
            return Array(chars[index ..< index + target.count]) == target
        }

        private func matchesCaseInsensitive(_ target: [Character]) -> Bool {
            guard index + target.count <= chars.count else { return false }
            for (offset, character) in target.enumerated() where !Self.sameLetter(character, chars[index + offset]) {
                return false
            }
            return true
        }

        private static func sameLetter(_ lhs: Character, _ rhs: Character) -> Bool {
            lhs.lowercased() == rhs.lowercased()
        }

        @discardableResult
        private mutating func advance() -> Character? {
            guard !isAtEnd else { return nil }
            defer { index += 1 }
            return chars[index]
        }

        @discardableResult
        private mutating func consume(_ literal: String) -> Bool {
            guard matches(literal) else { return false }
            index += literal.count
            return true
        }

        private mutating func skipSpace() {
            while let character = peek(), character.isWhitespace {
                advance()
            }
        }

        private mutating func skipUntil(_ character: Character) {
            while let current = peek(), current != character {
                advance()
            }
            advance()
        }
    }
}
