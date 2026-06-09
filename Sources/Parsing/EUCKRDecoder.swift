extension PureXML.Parsing.ByteDecoder {
    /// The EUC-KR (CP949/UHC) index, assembled from the vendored parts.
    static let eucKR: [UInt16] = eucKRPart1 + eucKRPart2 + eucKRPart3 + eucKRPart4 + eucKRPart5 + eucKRPart6

    /// The EUC-KR decoder (the WHATWG `EUC-KR` algorithm): ASCII directly, any
    /// other byte in `0x81`-`0xFE` as a lead followed by a trail resolved through
    /// the CP949 index.
    enum EUCKR {
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
                } else if (0x81 ... 0xFE).contains(byte) {
                    lead = byte
                } else {
                    scalars.append("\u{FFFD}")
                }
            }
            if lead != 0 { scalars.append("\u{FFFD}") }
            return String(scalars)
        }

        /// The scalar for a `(lead, trail)` pair through the CP949 index, or nil for
        /// an invalid or unmapped pair.
        static func twoByteScalar(lead: UInt8, trail: UInt8) -> Unicode.Scalar? {
            guard (0x41 ... 0xFE).contains(trail) else { return nil }
            let pointer = (Int(lead) - 0x81) * 190 + Int(trail) - 0x41
            guard pointer >= 0, pointer < eucKR.count, eucKR[pointer] != 0xFFFF else { return nil }
            return Unicode.Scalar(UInt32(eucKR[pointer]))
        }
    }
}
