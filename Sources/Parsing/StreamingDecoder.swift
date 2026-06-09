extension PureXML.Parsing {
    /// Decodes a byte stream into characters incrementally. It detects the
    /// encoding from the leading bytes (buffering only those few), strips any
    /// byte-order mark, then yields one Unicode scalar at a time as a Character,
    /// so a byte source is never fully materialized. Invalid sequences yield the
    /// Unicode replacement character rather than failing the stream.
    ///
    /// This works at scalar granularity; a multi-scalar grapheme cluster is
    /// surfaced as separate characters, which is harmless for XML tokenization.
    struct StreamingDecoder {
        private let pull: () -> UInt8?
        private var encoding: InputEncoding?
        private var prefix: [UInt8] = []
        private var prefixIndex = 0
        var finished = false
        var iso2022jpMode: ISO2022JPMode = .ascii

        static let replacement: Character = "\u{FFFD}"

        init(pullingBytes pull: @escaping () -> UInt8?) {
            self.pull = pull
        }

        /// Returns the next decoded character, or nil at the end of the stream.
        mutating func next() -> Character? {
            if encoding == nil {
                detect()
            }
            guard !finished, let encoding else {
                return nil
            }
            if let map = PureXML.Parsing.ByteDecoder.singleByteMap(encoding) {
                return nextSingleByte(map)
            }
            return nextWide(encoding)
        }

        /// Dispatches the non-single-byte encodings (the Unicode transformation
        /// formats and the multi-byte CJK encodings).
        private mutating func nextWide(_ encoding: InputEncoding) -> Character? {
            switch encoding {
            case .utf16BigEndian: nextUTF16(bigEndian: true)
            case .utf16LittleEndian: nextUTF16(bigEndian: false)
            case .utf32BigEndian: nextUTF32(bigEndian: true)
            case .utf32LittleEndian: nextUTF32(bigEndian: false)
            default: nextCJK(encoding)
            }
        }

        /// Streams one character from a multi-byte CJK encoding.
        private mutating func nextCJK(_ encoding: InputEncoding) -> Character? {
            switch encoding {
            case .shiftJIS: nextShiftJIS()
            case .eucJP: nextEUCJP()
            case .eucKR: nextEUCKR()
            case .gbk: nextGBK()
            case .gb18030: nextGB18030()
            case .big5: nextBig5()
            case .iso2022jp: nextISO2022JP()
            default: nextUTF8()
            }
        }

        /// Streams one GBK character: ASCII, `0x80` (euro), or a lead+trail.
        private mutating func nextGBK() -> Character? {
            guard let lead = nextByte() else {
                finished = true
                return nil
            }
            if lead <= 0x7F { return Character(Unicode.Scalar(lead)) }
            if lead == 0x80 { return "\u{20AC}" }
            guard (0x81 ... 0xFE).contains(lead) else { return Self.replacement }
            guard let trail = nextByte() else { finished = true
                return Self.replacement
            }
            return PureXML.Parsing.ByteDecoder.GBK.twoByteScalar(lead: lead, trail: trail).map(Character.init) ?? Self.replacement
        }

        /// Streams one GB18030 character: ASCII, `0x80` (euro), a four-byte
        /// sequence when the lead is followed by a digit, or a two-byte GBK pair.
        private mutating func nextGB18030() -> Character? {
            guard let lead = nextByte() else {
                finished = true
                return nil
            }
            if lead <= 0x7F { return Character(Unicode.Scalar(lead)) }
            if lead == 0x80 { return "\u{20AC}" }
            guard (0x81 ... 0xFE).contains(lead) else { return Self.replacement }
            guard let second = nextByte() else { finished = true
                return Self.replacement
            }
            if (0x30 ... 0x39).contains(second) {
                guard let third = nextByte(), let fourth = nextByte() else { finished = true
                    return Self.replacement
                }
                guard (0x81 ... 0xFE).contains(third), (0x30 ... 0x39).contains(fourth) else { return Self.replacement }
                let pointer = PureXML.Parsing.ByteDecoder.GB18030.fourBytePointer(lead, second, third, fourth)
                return PureXML.Parsing.ByteDecoder.GB18030.rangeScalar(pointer).map(Character.init) ?? Self.replacement
            }
            return PureXML.Parsing.ByteDecoder.GBK.twoByteScalar(lead: lead, trail: second).map(Character.init) ?? Self.replacement
        }

        /// Streams one Big5 character: ASCII, or a lead+trail through the index
        /// (a two-scalar combining sequence stays one grapheme, one `Character`).
        private mutating func nextBig5() -> Character? {
            guard let lead = nextByte() else {
                finished = true
                return nil
            }
            if lead <= 0x7F { return Character(Unicode.Scalar(lead)) }
            guard (0x81 ... 0xFE).contains(lead) else { return Self.replacement }
            guard let trail = nextByte() else { finished = true
                return Self.replacement
            }
            guard let sequence = PureXML.Parsing.ByteDecoder.Big5.mapping(lead: lead, trail: trail) else {
                return Self.replacement
            }
            return Character(String(String.UnicodeScalarView(sequence)))
        }

        /// Streams one EUC-KR character: ASCII, or a lead+trail through CP949.
        private mutating func nextEUCKR() -> Character? {
            guard let lead = nextByte() else {
                finished = true
                return nil
            }
            if lead <= 0x7F { return Character(Unicode.Scalar(lead)) }
            guard (0x81 ... 0xFE).contains(lead) else { return Self.replacement }
            guard let trail = nextByte() else { finished = true
                return Self.replacement
            }
            return PureXML.Parsing.ByteDecoder.EUCKR.twoByteScalar(lead: lead, trail: trail).map(Character.init) ?? Self.replacement
        }

        /// Streams one EUC-JP character: ASCII, `0x8E`+byte (half-width katakana),
        /// `0x8F`+two bytes (JIS X 0212), or a lead+byte through JIS X 0208.
        private mutating func nextEUCJP() -> Character? {
            guard let lead = nextByte() else {
                finished = true
                return nil
            }
            if lead <= 0x7F { return Character(Unicode.Scalar(lead)) }
            if lead == 0x8E {
                guard let byte = nextByte() else { finished = true
                    return Self.replacement
                }
                guard (0xA1 ... 0xDF).contains(byte) else { return Self.replacement }
                return Character(Unicode.Scalar(0xFF61 + UInt32(byte) - 0xA1) ?? "\u{FFFD}")
            }
            if lead == 0x8F {
                guard let mid = nextByte(), let trail = nextByte() else { finished = true
                    return Self.replacement
                }
                return PureXML.Parsing.ByteDecoder.EUCJP.twoByteScalar(lead: mid, trail: trail, useJis0212: true).map(Character.init) ?? Self.replacement
            }
            guard let trail = nextByte() else { finished = true
                return Self.replacement
            }
            return PureXML.Parsing.ByteDecoder.EUCJP.twoByteScalar(lead: lead, trail: trail, useJis0212: false).map(Character.init) ?? Self.replacement
        }

        /// Streams one Shift-JIS character: a single byte (ASCII or half-width
        /// katakana) or a lead+trail two-byte sequence resolved through JIS X 0208.
        private mutating func nextShiftJIS() -> Character? {
            guard let lead = nextByte() else {
                finished = true
                return nil
            }
            if let single = PureXML.Parsing.ByteDecoder.ShiftJIS.singleByteScalar(lead) { return Character(single) }
            guard PureXML.Parsing.ByteDecoder.ShiftJIS.isLead(lead) else { return Self.replacement }
            guard let trail = nextByte() else {
                finished = true
                return Self.replacement
            }
            guard let scalar = PureXML.Parsing.ByteDecoder.ShiftJIS.twoByteScalar(lead: lead, trail: trail) else { return Self.replacement }
            return Character(scalar)
        }

        private mutating func nextUTF32(bigEndian: Bool) -> Character? {
            var ordered: [UInt32] = []
            for _ in 0 ..< 4 {
                guard let byte = nextByte() else {
                    finished = true
                    return nil
                }
                ordered.append(UInt32(byte))
            }
            if !bigEndian { ordered.reverse() }
            let value = ordered.reduce(UInt32(0)) { ($0 << 8) | $1 }
            return Character(Unicode.Scalar(value) ?? "\u{FFFD}")
        }

        private mutating func nextSingleByte(_ map: (UInt8) -> Unicode.Scalar) -> Character? {
            guard let byte = nextByte() else {
                finished = true
                return nil
            }
            return Character(map(byte))
        }

        private mutating func detect() {
            while prefix.count < 4, let byte = pull() {
                prefix.append(byte)
            }
            let detected = InputEncoding.detectWithBOM(prefix)
            prefixIndex = detected.bomLength
            encoding = detected.encoding
            // With no byte-order mark and an ASCII-compatible default, the XML
            // declaration may name another encoding (the libxml2 behavior). Buffer
            // through the declaration and honor it; the ASCII declaration bytes
            // decode identically under the chosen encoding when replayed.
            if detected.bomLength == 0, detected.encoding == .utf8 {
                while prefix.count < 256, !prefix.contains(0x3E), let byte = pull() {
                    prefix.append(byte)
                }
                if let declared = PureXML.Parsing.ByteDecoder.declaredEncoding(in: prefix) {
                    encoding = declared
                }
            }
        }

        mutating func nextByte() -> UInt8? {
            if prefixIndex < prefix.count {
                let byte = prefix[prefixIndex]
                prefixIndex += 1
                return byte
            }
            return pull()
        }

        private mutating func nextUTF8() -> Character? {
            guard let first = nextByte() else {
                finished = true
                return nil
            }
            if first < 0x80 {
                return Character(Unicode.Scalar(first))
            }
            let length: Int
            var value: UInt32
            if first & 0xE0 == 0xC0 {
                length = 2
                value = UInt32(first & 0x1F)
            } else if first & 0xF0 == 0xE0 {
                length = 3
                value = UInt32(first & 0x0F)
            } else if first & 0xF8 == 0xF0 {
                length = 4
                value = UInt32(first & 0x07)
            } else {
                return Self.replacement
            }
            for _ in 1 ..< length {
                guard let continuation = nextByte(), continuation & 0xC0 == 0x80 else {
                    return Self.replacement
                }
                value = (value << 6) | UInt32(continuation & 0x3F)
            }
            guard let scalar = Unicode.Scalar(value) else {
                return Self.replacement
            }
            return Character(scalar)
        }

        private mutating func nextUTF16(bigEndian: Bool) -> Character? {
            guard let unit = nextUnit(bigEndian: bigEndian) else {
                finished = true
                return nil
            }
            if (0xD800 ... 0xDBFF).contains(unit) {
                guard let low = nextUnit(bigEndian: bigEndian), (0xDC00 ... 0xDFFF).contains(low) else {
                    return Self.replacement
                }
                let value = 0x10000 + (UInt32(unit - 0xD800) << 10) + UInt32(low - 0xDC00)
                guard let scalar = Unicode.Scalar(value) else {
                    return Self.replacement
                }
                return Character(scalar)
            }
            guard let scalar = Unicode.Scalar(unit) else {
                return Self.replacement
            }
            return Character(scalar)
        }

        private mutating func nextUnit(bigEndian: Bool) -> UInt16? {
            guard let high = nextByte(), let low = nextByte() else {
                return nil
            }
            return bigEndian ? (UInt16(high) << 8 | UInt16(low)) : (UInt16(low) << 8 | UInt16(high))
        }
    }
}
