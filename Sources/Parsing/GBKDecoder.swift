extension PureXML.Parsing.ByteDecoder {
    /// The GBK index (the GB18030 two-byte range), assembled from the vendored
    /// parts. Decodes GB2312 too, which GBK is a superset of.
    static let gbk: [UInt16] = gbkPart1 + gbkPart2 + gbkPart3 + gbkPart4 + gbkPart5 + gbkPart6

    /// The GBK decoder (the WHATWG `GBK` algorithm, the two-byte subset of
    /// GB18030): ASCII directly, `0x80` as the euro sign, and a lead in
    /// `0x81`-`0xFE` followed by a trail resolved through the index.
    enum GBK {
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
                        if byte <= 0x7F { scalars.append(Unicode.Scalar(byte)) }
                    }
                } else if byte <= 0x7F {
                    scalars.append(Unicode.Scalar(byte))
                } else if byte == 0x80 {
                    scalars.append("\u{20AC}") // euro
                } else if (0x81 ... 0xFE).contains(byte) {
                    lead = byte
                } else {
                    scalars.append("\u{FFFD}")
                }
            }
            if lead != 0 { scalars.append("\u{FFFD}") }
            return String(scalars)
        }

        /// The scalar for a `(lead, trail)` pair through the GBK index, or nil for
        /// an invalid or unmapped pair.
        static func twoByteScalar(lead: UInt8, trail: UInt8) -> Unicode.Scalar? {
            guard (0x40 ... 0x7E).contains(trail) || (0x80 ... 0xFE).contains(trail) else { return nil }
            let offset = trail < 0x7F ? 0x40 : 0x41
            let pointer = (Int(lead) - 0x81) * 190 + Int(trail) - offset
            guard pointer >= 0, pointer < gbk.count, gbk[pointer] != 0xFFFF else { return nil }
            return Unicode.Scalar(UInt32(gbk[pointer]))
        }
    }
}
