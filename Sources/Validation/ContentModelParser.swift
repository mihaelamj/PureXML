extension PureXML.Validation {
    /// Parses a DTD content-model string (the text after `<!ELEMENT name`) into a
    /// ``ContentModel``. Tolerant: a malformed model falls back to `ANY` rather
    /// than failing, so a damaged DTD never blocks parsing the document itself.
    struct ContentModelParser {
        private let chars: [Character]
        private var index = 0

        private init(_ model: String) {
            chars = Array(model)
        }

        static func parse(_ model: String) -> ContentModel {
            var parser = ContentModelParser(model)
            return parser.parseModel()
        }

        private mutating func parseModel() -> ContentModel {
            skipSpace()
            if matchKeyword("EMPTY") { return .empty }
            if matchKeyword("ANY") { return .any }
            guard peek() == "(" else { return .any }

            // Look inside for the #PCDATA marker to distinguish mixed/PCDATA from
            // element content, without consuming the group.
            let saved = index
            advance()
            skipSpace()
            if matchKeyword("#PCDATA") {
                return parseMixedTail()
            }
            index = saved
            return .children(parseParticle())
        }

        private mutating func parseMixedTail() -> ContentModel {
            var names: [String] = []
            while true {
                skipSpace()
                if peek() == ")" { advance()
                    break
                }
                if peek() == "|" {
                    advance()
                    skipSpace()
                    let name = parseName()
                    if !name.isEmpty { names.append(name) }
                } else {
                    advance()
                }
            }
            _ = consumeOccurrence()
            return names.isEmpty ? .pcdata : .mixed(names)
        }

        private mutating func parseParticle() -> Particle {
            skipSpace()
            if peek() == "(" {
                advance()
                var items: [Particle] = [parseParticle()]
                var separator: Character?
                while true {
                    skipSpace()
                    guard let next = peek(), next == "," || next == "|" else { break }
                    separator = separator ?? next
                    advance()
                    items.append(parseParticle())
                }
                skipSpace()
                if peek() == ")" { advance() }
                let occurrence = consumeOccurrence()
                return separator == "|" ? .choice(items, occurrence) : .sequence(items, occurrence)
            }
            let name = parseName()
            return .name(name, consumeOccurrence())
        }

        private mutating func consumeOccurrence() -> Occurrence {
            switch peek() {
            case "?": advance()
                return .optional
            case "*": advance()
                return .zeroOrMore
            case "+": advance()
                return .oneOrMore
            default: return .once
            }
        }

        private mutating func parseName() -> String {
            var name = ""
            while let character = peek(), !isDelimiter(character) {
                name.append(character)
                advance()
            }
            return name
        }

        private func isDelimiter(_ character: Character) -> Bool {
            switch character {
            case ",", "|", "(", ")", "?", "*", "+", " ", "\t", "\n", "\r": true
            default: false
            }
        }

        private mutating func matchKeyword(_ keyword: String) -> Bool {
            let target = Array(keyword)
            guard index + target.count <= chars.count else { return false }
            for (offset, expected) in target.enumerated() where chars[index + offset] != expected {
                return false
            }
            index += target.count
            return true
        }

        private func peek() -> Character? {
            index < chars.count ? chars[index] : nil
        }

        private mutating func advance() {
            if index < chars.count { index += 1 }
        }

        private mutating func skipSpace() {
            while let character = peek(), character == " " || character == "\t" || character == "\n" || character == "\r" {
                advance()
            }
        }
    }
}
