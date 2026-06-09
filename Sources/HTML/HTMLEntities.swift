extension PureXML.HTML.Tokenizer {
    /// The HTML numeric-character-reference fixups for the Windows-1252 C1 range
    /// (`0x80`–`0x9F`): a reference to one of these code points yields the mapped
    /// character rather than the C1 control, per the HTML standard.
    private static let c1Replacements: [UInt32: UInt32] = [
        0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026,
        0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160,
        0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019,
        0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014,
        0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153,
        0x9E: 0x017E, 0x9F: 0x0178,
    ]

    private static let replacementCharacter: Character = "\u{FFFD}"

    /// Replaces NUL with U+FFFD, the HTML rule for the literal null byte in
    /// character data (it never reaches the document as U+0000).
    static func replacingNull(_ value: String) -> String {
        guard value.contains("\u{0}") else { return value }
        return String(value.map { $0 == "\u{0}" ? replacementCharacter : $0 })
    }

    /// Decodes the HTML character references in `value`: named references (with or
    /// without a trailing semicolon, longest match wins) and numeric references
    /// (decimal `&#...;` or hex `&#x...;`) with range, surrogate, and C1 fixups.
    /// An unrecognized `&...` sequence is left as written (the lenient behavior).
    static func decodeEntities(_ value: String) -> String {
        guard value.contains("&") else { return value }
        let characters = Array(value)
        var result = ""
        var index = 0
        while index < characters.count {
            guard characters[index] == "&" else {
                result.append(characters[index])
                index += 1
                continue
            }
            if let (text, consumed) = decodeReference(characters, at: index) {
                result += text
                index += consumed
            } else {
                result.append("&")
                index += 1
            }
        }
        return result
    }

    /// Decodes a single reference starting at the `&` in `characters[start]`,
    /// returning its replacement text and how many characters it consumed, or nil
    /// when there is no valid reference there.
    private static func decodeReference(_ characters: [Character], at start: Int) -> (String, Int)? {
        if start + 1 < characters.count, characters[start + 1] == "#" {
            return decodeNumeric(characters, at: start)
        }
        return decodeNamed(characters, at: start)
    }

    private static func decodeNumeric(_ characters: [Character], at start: Int) -> (String, Int)? {
        var cursor = start + 2 // past "&#"
        let isHex = cursor < characters.count && (characters[cursor] == "x" || characters[cursor] == "X")
        if isHex { cursor += 1 }
        let digitsStart = cursor
        while cursor < characters.count, isDigit(characters[cursor], hex: isHex) {
            cursor += 1
        }
        guard cursor > digitsStart, let number = UInt32(String(characters[digitsStart ..< cursor]), radix: isHex ? 16 : 10) else { return nil }
        if cursor < characters.count, characters[cursor] == ";" { cursor += 1 }
        return (String(numericCharacter(number)), cursor - start)
    }

    /// The character a numeric reference resolves to: U+FFFD for zero, surrogates,
    /// and out-of-range values; the C1 fixup for `0x80`–`0x9F`; otherwise the code
    /// point itself.
    private static func numericCharacter(_ number: UInt32) -> Character {
        if let replacement = c1Replacements[number] {
            return Unicode.Scalar(replacement).map(Character.init) ?? replacementCharacter
        }
        if number == 0 || number > 0x10FFFF || (0xD800 ... 0xDFFF).contains(number) {
            return replacementCharacter
        }
        return Unicode.Scalar(number).map(Character.init) ?? replacementCharacter
    }

    private static func decodeNamed(_ characters: [Character], at start: Int) -> (String, Int)? {
        var cursor = start + 1
        var name = ""
        // The longest name in the table is short; cap the scan accordingly.
        while cursor < characters.count, characters[cursor].isLetter || characters[cursor].isNumber, name.count < 12 {
            name.append(characters[cursor])
            cursor += 1
        }
        // Longest match wins: shrink the candidate until it names an entity.
        while !name.isEmpty {
            if let character = namedEntities[name] {
                let end = start + 1 + name.count
                let semicolon = end < characters.count && characters[end] == ";"
                return (String(character), name.count + 1 + (semicolon ? 1 : 0))
            }
            name.removeLast()
        }
        return nil
    }

    private static func isDigit(_ character: Character, hex: Bool) -> Bool {
        hex ? character.isHexDigit : character.isNumber
    }
}
