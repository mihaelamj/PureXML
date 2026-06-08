extension PureXML.HTML.Tokenizer {
    private static let named: [String: Character] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{A0}", "copy": "\u{A9}", "reg": "\u{AE}", "trade": "\u{2122}",
        "mdash": "\u{2014}", "ndash": "\u{2013}", "hellip": "\u{2026}",
        "laquo": "\u{AB}", "raquo": "\u{BB}", "deg": "\u{B0}", "euro": "\u{20AC}",
    ]

    /// Decodes the common HTML character references in `value`, leaving any
    /// unrecognized `&...;` sequence as written (the lenient HTML behavior).
    static func decodeEntities(_ value: String) -> String {
        guard value.contains("&") else { return value }
        var result = ""
        let characters = Array(value)
        var index = 0
        while index < characters.count {
            guard characters[index] == "&", let semicolon = nextSemicolon(characters, after: index) else {
                result.append(characters[index])
                index += 1
                continue
            }
            let body = String(characters[(index + 1) ..< semicolon])
            if let decoded = decode(body) {
                result.append(decoded)
                index = semicolon + 1
            } else {
                result.append("&")
                index += 1
            }
        }
        return result
    }

    private static func nextSemicolon(_ characters: [Character], after start: Int) -> Int? {
        var index = start + 1
        while index < characters.count, index - start <= 10 {
            if characters[index] == ";" { return index }
            index += 1
        }
        return nil
    }

    private static func decode(_ body: String) -> Character? {
        if let named = named[body] { return named }
        guard body.hasPrefix("#") else { return nil }
        let digits = body.dropFirst()
        let scalar: UInt32? = if digits.hasPrefix("x") || digits.hasPrefix("X") {
            UInt32(digits.dropFirst(), radix: 16)
        } else {
            UInt32(digits, radix: 10)
        }
        return scalar.flatMap(Unicode.Scalar.init).map(Character.init)
    }
}
