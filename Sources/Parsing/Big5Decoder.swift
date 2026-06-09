extension PureXML.Parsing.ByteDecoder {
    /// The Big5 decoder (the WHATWG `big5` algorithm): ASCII directly, and a lead
    /// in `0x81`-`0xFE` followed by a trail in `0x40`-`0x7E` or `0xA1`-`0xFE`
    /// resolved through the index. Four pointers decode to a base letter plus a
    /// combining mark (a two-scalar sequence); the rest are single scalars,
    /// including the astral HKSCS ideographs.
    enum Big5 {
        static func decode(_ bytes: ArraySlice<UInt8>) -> String {
            var scalars = String.UnicodeScalarView()
            var lead: UInt8 = 0
            for byte in bytes {
                if lead != 0 {
                    let saved = lead
                    lead = 0
                    if let sequence = mapping(lead: saved, trail: byte) {
                        scalars.append(contentsOf: sequence)
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

        /// The scalar sequence for a `(lead, trail)` pair through the Big5 index,
        /// or nil for an invalid or unmapped pair. Most pairs map to one scalar;
        /// four pointers map to a base letter plus a combining mark.
        static func mapping(lead: UInt8, trail: UInt8) -> [Unicode.Scalar]? {
            guard (0x40 ... 0x7E).contains(trail) || (0xA1 ... 0xFE).contains(trail) else { return nil }
            let offset = trail < 0x7F ? 0x40 : 0x62
            let pointer = (Int(lead) - 0x81) * 157 + Int(trail) - offset
            switch pointer {
            case 1133: return ["\u{00CA}", "\u{0304}"]
            case 1135: return ["\u{00CA}", "\u{030C}"]
            case 1164: return ["\u{00EA}", "\u{0304}"]
            case 1166: return ["\u{00EA}", "\u{030C}"]
            default: break
            }
            let index = pointer - big5Base
            guard index >= 0, index < big5.count, big5[index] != 0,
                  let scalar = Unicode.Scalar(big5[index])
            else { return nil }
            return [scalar]
        }
    }
}
