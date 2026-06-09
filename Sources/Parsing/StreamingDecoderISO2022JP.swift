extension PureXML.Parsing.StreamingDecoder {
    /// Streams one ISO-2022-JP character, carrying the active mode across calls.
    /// Escape sequences switch mode and yield no character, so it loops until a
    /// character is produced or the stream ends.
    mutating func nextISO2022JP() -> Character? {
        while true {
            guard let byte = nextByte() else {
                finished = true
                return nil
            }
            if byte == 0x1B {
                guard applyISO2022JPEscape() else { return Self.replacement }
                continue
            }
            return decodeISO2022JPByte(byte)
        }
    }

    private mutating func decodeISO2022JPByte(_ byte: UInt8) -> Character {
        switch iso2022jpMode {
        case .ascii:
            return byte <= 0x7F ? Character(Unicode.Scalar(byte)) : Self.replacement
        case .roman:
            return romanScalar(byte)
        case .katakana:
            guard (0x21 ... 0x5F).contains(byte) else { return Self.replacement }
            return Character(Unicode.Scalar(0xFF61 + UInt32(byte) - 0x21) ?? "\u{FFFD}")
        case .jis0208:
            return jis0208Character(byte)
        }
    }

    private func romanScalar(_ byte: UInt8) -> Character {
        switch byte {
        case 0x5C: "\u{00A5}" // yen
        case 0x7E: "\u{203E}" // overline
        case 0 ... 0x7F: Character(Unicode.Scalar(byte))
        default: Self.replacement
        }
    }

    private mutating func jis0208Character(_ lead: UInt8) -> Character {
        guard (0x21 ... 0x7E).contains(lead) else {
            return lead == 0x0A || lead == 0x0D ? Character(Unicode.Scalar(lead)) : Self.replacement
        }
        guard let trail = nextByte() else {
            finished = true
            return Self.replacement
        }
        guard (0x21 ... 0x7E).contains(trail) else { return Self.replacement }
        let pointer = (Int(lead) - 0x21) * 94 + Int(trail) - 0x21
        let table = PureXML.Parsing.ByteDecoder.jis0208
        guard pointer >= 0, pointer < table.count, table[pointer] != 0xFFFF else { return Self.replacement }
        return Character(Unicode.Scalar(UInt32(table[pointer])) ?? "\u{FFFD}")
    }

    private mutating func applyISO2022JPEscape() -> Bool {
        guard let first = nextByte(), let second = nextByte() else {
            finished = true
            return false
        }
        switch (first, second) {
        case (0x28, 0x42): iso2022jpMode = .ascii
        case (0x28, 0x4A): iso2022jpMode = .roman
        case (0x28, 0x49): iso2022jpMode = .katakana
        case (0x24, 0x40), (0x24, 0x42): iso2022jpMode = .jis0208
        default: return false
        }
        return true
    }
}
