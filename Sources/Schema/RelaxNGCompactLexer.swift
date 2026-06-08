extension PureXML.Schema {
    /// One lexical token of the RELAX NG compact syntax.
    enum RNCToken: Equatable {
        case word(String)
        case string(String)
        case symbol(String)
    }

    /// Tokenizes RELAX NG compact-syntax source: NCName words (which may carry a
    /// single `:` prefix), quoted string literals, and punctuation, with `#`
    /// line comments skipped.
    enum RNCLexer {
        static func tokens(_ source: String) -> [RNCToken] {
            var tokens: [RNCToken] = []
            let characters = Array(source)
            var index = 0
            while index < characters.count {
                let character = characters[index]
                if character == "#" {
                    while index < characters.count, characters[index] != "\n" {
                        index += 1
                    }
                } else if character.isWhitespace {
                    index += 1
                } else if character == "\"" || character == "'" {
                    index = readString(characters, index, quote: character, into: &tokens)
                } else if isNameStart(character) {
                    index = readWord(characters, index, into: &tokens)
                } else {
                    index = readSymbol(characters, index, into: &tokens)
                }
            }
            return tokens
        }

        private static func readString(_ characters: [Character], _ start: Int, quote: Character, into tokens: inout [RNCToken]) -> Int {
            var index = start + 1
            var value = ""
            while index < characters.count, characters[index] != quote {
                value.append(characters[index])
                index += 1
            }
            tokens.append(.string(value))
            return index + 1
        }

        private static func readWord(_ characters: [Character], _ start: Int, into tokens: inout [RNCToken]) -> Int {
            var index = start
            var value = ""
            while index < characters.count, isNameChar(characters[index]) {
                value.append(characters[index])
                index += 1
            }
            tokens.append(.word(value))
            return index
        }

        private static func readSymbol(_ characters: [Character], _ start: Int, into tokens: inout [RNCToken]) -> Int {
            let two = start + 1 < characters.count ? String(characters[start ... start + 1]) : ""
            if two == "|=" || two == "&=" {
                tokens.append(.symbol(two))
                return start + 2
            }
            tokens.append(.symbol(String(characters[start])))
            return start + 1
        }

        private static func isNameStart(_ character: Character) -> Bool {
            character.isLetter || character == "_"
        }

        private static func isNameChar(_ character: Character) -> Bool {
            character.isLetter || character.isNumber || character == "_" || character == "." || character == "-" || character == ":"
        }
    }
}
