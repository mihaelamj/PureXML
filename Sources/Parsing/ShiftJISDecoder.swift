extension PureXML.Parsing.ByteDecoder {
    /// The JIS X 0208 index (pointer -> code point), assembled from the vendored
    /// parts. `0xFFFF` marks an unmapped pointer.
    static let jis0208: [UInt16] = jis0208Part1 + jis0208Part2 + jis0208Part3

    /// The Shift-JIS decoder (the WHATWG `Shift_JIS` algorithm). Single bytes cover
    /// ASCII and half-width katakana; a lead byte introduces a two-byte sequence
    /// resolved through the JIS X 0208 index.
    enum ShiftJIS {
        /// Decodes a whole Shift-JIS byte buffer.
        static func decode(_ bytes: ArraySlice<UInt8>) -> String {
            var scalars = String.UnicodeScalarView()
            var lead: UInt8 = 0
            for byte in bytes {
                if lead != 0 {
                    let saved = lead
                    lead = 0
                    if let scalar = twoByteScalar(lead: saved, trail: byte) {
                        scalars.append(scalar)
                    } else {
                        scalars.append("\u{FFFD}")
                        if byte <= 0x7F { scalars.append(Unicode.Scalar(byte)) } // reprocess ASCII trail
                    }
                } else if let single = singleByteScalar(byte) {
                    scalars.append(single)
                } else if isLead(byte) {
                    lead = byte
                } else {
                    scalars.append("\u{FFFD}")
                }
            }
            if lead != 0 { scalars.append("\u{FFFD}") }
            return String(scalars)
        }

        /// The scalar for a byte that is not part of a two-byte sequence: ASCII
        /// (`0x00`-`0x80`) or half-width katakana (`0xA1`-`0xDF`), else nil.
        static func singleByteScalar(_ byte: UInt8) -> Unicode.Scalar? {
            if byte <= 0x80 { return Unicode.Scalar(byte) }
            if (0xA1 ... 0xDF).contains(byte) { return Unicode.Scalar(0xFF61 + UInt32(byte) - 0xA1) }
            return nil
        }

        /// Whether a byte introduces a two-byte sequence.
        static func isLead(_ byte: UInt8) -> Bool {
            (0x81 ... 0x9F).contains(byte) || (0xE0 ... 0xFC).contains(byte)
        }

        /// The scalar for a `(lead, trail)` pair, or nil when the pair is invalid
        /// or unmapped.
        static func twoByteScalar(lead: UInt8, trail: UInt8) -> Unicode.Scalar? {
            guard (0x40 ... 0x7E).contains(trail) || (0x80 ... 0xFC).contains(trail) else { return nil }
            let offset = lead < 0xA0 ? 0x81 : 0xC1
            let trailOffset = trail < 0x7F ? 0x40 : 0x41
            let pointer = (Int(lead) - offset) * 188 + Int(trail) - trailOffset
            if (8836 ... 10715).contains(pointer) { return Unicode.Scalar(0xE000 + pointer - 8836) } // EUDC private use
            guard pointer >= 0, pointer < jis0208.count, jis0208[pointer] != 0xFFFF else { return nil }
            return Unicode.Scalar(UInt32(jis0208[pointer]))
        }
    }
}
