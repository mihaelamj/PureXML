extension PureXML.Parsing.ByteEncoder {
    private typealias Decoder = PureXML.Parsing.ByteDecoder

    /// The bytes of `string` in a multi-byte CJK encoding, or nil for a
    /// non-CJK encoding. Each inverse is built by running the existing,
    /// tested whole-buffer decoder over every valid byte sequence and
    /// recording the shortest sequence per scalar, so the encoder is by
    /// construction the exact inverse of the decoder.
    static func cjkEncode(_ string: String, as encoding: PureXML.Parsing.InputEncoding) -> [UInt8]? {
        let inverse: [UInt32: [UInt8]]
        switch encoding {
        case .shiftJIS: inverse = shiftJISInverse
        case .eucJP: inverse = eucJPInverse
        case .eucKR: inverse = eucKRInverse
        case .gbk: inverse = gbkInverse
        case .big5: inverse = big5Inverse
        case .gb18030: return gb18030Encode(string)
        default: return nil
        }
        return mapped(string, through: inverse)
    }

    static func supportsCJK(_ encoding: PureXML.Parsing.InputEncoding) -> Bool {
        switch encoding {
        case .shiftJIS, .eucJP, .eucKR, .gbk, .big5, .gb18030: true
        default: false
        }
    }

    private static func mapped(_ string: String, through inverse: [UInt32: [UInt8]]) -> [UInt8] {
        var bytes: [UInt8] = []
        for scalar in string.unicodeScalars {
            if scalar.value < 0x80 {
                bytes.append(UInt8(scalar.value))
            } else if let sequence = inverse[scalar.value] {
                bytes.append(contentsOf: sequence)
            } else {
                bytes.append(contentsOf: Array("&#\(scalar.value);".utf8))
            }
        }
        return bytes
    }

    // MARK: GB18030 (two-byte plus the four-byte ranges, a full Unicode encoding)

    private static func gb18030Encode(_ string: String) -> [UInt8] {
        var bytes: [UInt8] = []
        for scalar in string.unicodeScalars {
            if scalar.value < 0x80 {
                bytes.append(UInt8(scalar.value))
            } else if let sequence = gbkInverse[scalar.value] {
                bytes.append(contentsOf: sequence)
            } else {
                bytes.append(contentsOf: gb18030FourBytes(scalar.value))
            }
        }
        return bytes
    }

    /// The four-byte GB18030 sequence for a scalar, the inverse of the decoder's
    /// pointer-to-scalar range mapping.
    private static func gb18030FourBytes(_ codepoint: UInt32) -> [UInt8] {
        let pointers = Decoder.gb18030RangePointers
        let codepoints = Decoder.gb18030RangeCodePoints
        var low = 0
        var high = codepoints.count - 1
        var found = 0
        while low <= high {
            let mid = (low + high) / 2
            if codepoints[mid] <= codepoint {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        let pointer = Int(pointers[found]) + Int(codepoint - codepoints[found])
        let byte1 = pointer / 12600
        var rest = pointer % 12600
        let byte2 = rest / 1260
        rest %= 1260
        let byte3 = rest / 10
        let byte4 = rest % 10
        return [UInt8(byte1 + 0x81), UInt8(byte2 + 0x30), UInt8(byte3 + 0x81), UInt8(byte4 + 0x30)]
    }

    // MARK: Inverse tables, built once from the decoders

    private static let shiftJISInverse = buildInverse(Decoder.ShiftJIS.decode, leads: 0x81 ... 0xFE)
    private static let eucKRInverse = buildInverse(Decoder.EUCKR.decode, leads: 0x81 ... 0xFE)
    private static let gbkInverse = buildInverse(Decoder.GBK.decode, leads: 0x81 ... 0xFE)
    private static let big5Inverse = buildInverse(Decoder.Big5.decode, leads: 0x81 ... 0xFE)
    private static let eucJPInverse = buildInverse(Decoder.EUCJP.decode, leads: 0x8E ... 0xFE, threeByteLead: 0x8F)

    /// Enumerates every one-, two-, and (for EUC-JP) three-byte sequence the
    /// decoder accepts and records the scalar it yields. The first (shortest,
    /// lowest) sequence wins a scalar so the encoder stays deterministic.
    private static func buildInverse(
        _ decode: (ArraySlice<UInt8>) -> String,
        leads: ClosedRange<Int>,
        threeByteLead: UInt8? = nil,
    ) -> [UInt32: [UInt8]] {
        var map: [UInt32: [UInt8]] = [:]
        func record(_ bytes: [UInt8]) {
            let scalars = Array(decode(bytes[...]).unicodeScalars)
            guard scalars.count == 1, scalars[0].value != 0xFFFD, scalars[0].value >= 0x80 else { return }
            if map[scalars[0].value] == nil { map[scalars[0].value] = bytes }
        }
        for byte in 0x80 ... 0xFF {
            record([UInt8(byte)])
        }
        for lead in leads {
            for trail in 0x40 ... 0xFE {
                record([UInt8(lead), UInt8(trail)])
            }
        }
        if let threeByteLead {
            for middle in 0xA1 ... 0xFE {
                for trail in 0xA1 ... 0xFE {
                    record([threeByteLead, UInt8(middle), UInt8(trail)])
                }
            }
        }
        return map
    }
}
