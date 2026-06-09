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
        private var finished = false

        private static let replacement: Character = "\u{FFFD}"

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
            switch encoding {
            case .utf16BigEndian: return nextUTF16(bigEndian: true)
            case .utf16LittleEndian: return nextUTF16(bigEndian: false)
            case .utf32BigEndian: return nextUTF32(bigEndian: true)
            case .utf32LittleEndian: return nextUTF32(bigEndian: false)
            case .shiftJIS: return nextShiftJIS()
            default: return nextUTF8()
            }
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
            encoding = detected.encoding
            prefixIndex = detected.bomLength
        }

        private mutating func nextByte() -> UInt8? {
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
