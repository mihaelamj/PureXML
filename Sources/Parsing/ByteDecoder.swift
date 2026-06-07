extension PureXML.Parsing {
    /// Decodes raw bytes into a string using the detected encoding, stripping any
    /// byte-order mark. UTF-8 and UTF-16 (both byte orders) are supported, which
    /// is the encoding set the XML specification requires of every processor.
    /// Uses only the Swift standard library (no Foundation), so it stays portable.
    enum ByteDecoder {
        static func decode(_ bytes: [UInt8]) throws -> String {
            let (encoding, bomLength) = InputEncoding.detectWithBOM(bytes)
            let body = bytes.dropFirst(bomLength)
            switch encoding {
            case .utf8:
                return String(decoding: body, as: UTF8.self)
            case .utf16BigEndian:
                return try decodeUTF16(body, bigEndian: true)
            case .utf16LittleEndian:
                return try decodeUTF16(body, bigEndian: false)
            }
        }

        private static func decodeUTF16(_ bytes: ArraySlice<UInt8>, bigEndian: Bool) throws -> String {
            guard bytes.count.isMultiple(of: 2) else {
                throw PureXML.Parsing.ParseError.malformedEncoding
            }
            var units: [UInt16] = []
            units.reserveCapacity(bytes.count / 2)
            var iterator = bytes.makeIterator()
            while let first = iterator.next(), let second = iterator.next() {
                let high = UInt16(first)
                let low = UInt16(second)
                units.append(bigEndian ? (high << 8 | low) : (low << 8 | high))
            }
            return String(decoding: units, as: UTF16.self)
        }
    }
}
