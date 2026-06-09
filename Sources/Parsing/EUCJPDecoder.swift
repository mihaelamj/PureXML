extension PureXML.Parsing.ByteDecoder {
    /// The JIS X 0212 index, assembled from the vendored parts.
    static let jis0212: [UInt16] = jis0212Part1 + jis0212Part2

    /// The EUC-JP decoder (the WHATWG `EUC-JP` algorithm): ASCII directly, `0x8E`
    /// then a byte for half-width katakana, `0x8F` then two bytes through JIS X
    /// 0212, and any other lead byte then a byte through JIS X 0208.
    enum EUCJP {
        static func decode(_ bytes: ArraySlice<UInt8>) -> String {
            var scalars = String.UnicodeScalarView()
            var lead: UInt8 = 0
            var useJis0212 = false
            for byte in bytes {
                if lead == 0x8E, (0xA1 ... 0xDF).contains(byte) {
                    lead = 0
                    scalars.append(Unicode.Scalar(0xFF61 + UInt32(byte) - 0xA1) ?? "\u{FFFD}")
                } else if lead == 0x8F, (0xA1 ... 0xFE).contains(byte) {
                    useJis0212 = true
                    lead = byte
                } else if lead != 0 {
                    let saved = lead
                    lead = 0
                    let jis0212 = useJis0212
                    useJis0212 = false
                    if let scalar = twoByteScalar(lead: saved, trail: byte, useJis0212: jis0212) {
                        scalars.append(scalar)
                    } else {
                        scalars.append("\u{FFFD}")
                        if byte <= 0x7F { scalars.append(Unicode.Scalar(byte)) }
                    }
                } else if byte <= 0x7F {
                    scalars.append(Unicode.Scalar(byte))
                } else if byte == 0x8E || byte == 0x8F || (0xA1 ... 0xFE).contains(byte) {
                    lead = byte
                } else {
                    scalars.append("\u{FFFD}")
                }
            }
            if lead != 0 { scalars.append("\u{FFFD}") }
            return String(scalars)
        }

        /// The scalar for a `(lead, trail)` pair, resolved through JIS X 0212 when
        /// `useJis0212`, otherwise JIS X 0208. Nil for an invalid or unmapped pair.
        static func twoByteScalar(lead: UInt8, trail: UInt8, useJis0212: Bool) -> Unicode.Scalar? {
            guard (0xA1 ... 0xFE).contains(lead), (0xA1 ... 0xFE).contains(trail) else { return nil }
            let pointer = (Int(lead) - 0xA1) * 94 + Int(trail) - 0xA1
            let table = useJis0212 ? jis0212 : jis0208
            guard pointer >= 0, pointer < table.count, table[pointer] != 0xFFFF else { return nil }
            return Unicode.Scalar(UInt32(table[pointer]))
        }
    }
}
