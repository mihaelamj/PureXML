extension PureXML.Parsing.ByteDecoder {
    /// The GB18030 decoder (the WHATWG `gb18030` algorithm). It extends GBK with
    /// the four-byte sequences: a lead in `0x81`-`0xFE` followed by a digit
    /// (`0x30`-`0x39`) opens a four-byte form whose pointer is mapped through the
    /// linear ranges, reaching the astral planes. Two-byte pairs resolve through
    /// the shared GBK index.
    enum GB18030 {
        static func decode(_ bytes: ArraySlice<UInt8>) -> String {
            var scalars = String.UnicodeScalarView()
            var index = bytes.startIndex
            while index < bytes.endIndex {
                let byte = bytes[index]
                if byte <= 0x7F {
                    scalars.append(Unicode.Scalar(byte))
                    index += 1
                } else if byte == 0x80 {
                    scalars.append("\u{20AC}") // euro
                    index += 1
                } else if (0x81 ... 0xFE).contains(byte) {
                    index += step(bytes, index, byte, into: &scalars)
                } else {
                    scalars.append("\u{FFFD}")
                    index += 1
                }
            }
            return String(scalars)
        }

        /// Consumes one sequence starting at a lead byte and returns how many bytes
        /// it advanced. A digit second byte opens the four-byte form; anything else
        /// is a two-byte pair resolved through the GBK index.
        private static func step(
            _ bytes: ArraySlice<UInt8>,
            _ index: Int,
            _ lead: UInt8,
            into scalars: inout String.UnicodeScalarView,
        ) -> Int {
            guard index + 1 < bytes.endIndex else {
                scalars.append("\u{FFFD}")
                return 1
            }
            let second = bytes[index + 1]
            if (0x30 ... 0x39).contains(second) {
                guard index + 3 < bytes.endIndex,
                      (0x81 ... 0xFE).contains(bytes[index + 2]),
                      (0x30 ... 0x39).contains(bytes[index + 3])
                else {
                    scalars.append("\u{FFFD}")
                    return 1
                }
                let pointer = fourBytePointer(lead, second, bytes[index + 2], bytes[index + 3])
                scalars.append(rangeScalar(pointer) ?? "\u{FFFD}")
                return 4
            }
            if let scalar = GBK.twoByteScalar(lead: lead, trail: second) {
                scalars.append(scalar)
                return 2
            }
            scalars.append("\u{FFFD}")
            return second <= 0x7F ? 1 : 2
        }

        /// The four-byte pointer from a `(b1, b2, b3, b4)` sequence.
        static func fourBytePointer(_ byte1: UInt8, _ byte2: UInt8, _ byte3: UInt8, _ byte4: UInt8) -> Int {
            (Int(byte1) - 0x81) * 12600
                + (Int(byte2) - 0x30) * 1260
                + (Int(byte3) - 0x81) * 10
                + (Int(byte4) - 0x30)
        }

        /// The scalar for a four-byte pointer through the linear ranges, or nil for
        /// the unmapped gap and the out-of-range tail.
        static func rangeScalar(_ pointer: Int) -> Unicode.Scalar? {
            if pointer > 39419, pointer < 189_000 { return nil }
            if pointer > 1_237_575 { return nil }
            let target = UInt32(pointer)
            var low = 0
            var high = gb18030RangePointers.count - 1
            var found = 0
            while low <= high {
                let mid = (low + high) / 2
                if gb18030RangePointers[mid] <= target {
                    found = mid
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            let code = gb18030RangeCodePoints[found] + (target - gb18030RangePointers[found])
            return Unicode.Scalar(code)
        }
    }
}
