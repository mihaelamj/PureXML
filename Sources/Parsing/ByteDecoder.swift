extension PureXML.Parsing {
    /// Decodes raw bytes into a string using the detected encoding, stripping any
    /// byte-order mark. Covers UTF-8, UTF-16, and UTF-32 (both byte orders), plus
    /// ISO-8859-1 and Windows-1252 selected by the XML declaration's encoding
    /// name. Uses only the Swift standard library (no Foundation).
    enum ByteDecoder {
        static func decode(_ bytes: [UInt8]) throws -> String {
            let (sniffed, bomLength) = InputEncoding.detectWithBOM(bytes)
            // With no BOM the byte sniff defaults to UTF-8; honor a declared
            // single-byte encoding if the XML declaration names one.
            var encoding = sniffed
            if sniffed == .utf8, bomLength == 0, let declared = declaredEncoding(in: bytes) {
                encoding = declared
            }
            let body = bytes.dropFirst(bomLength)
            if let map = Self.singleByteMap(encoding) {
                return String(String.UnicodeScalarView(body.map(map)))
            }
            switch encoding {
            case .utf16BigEndian: return try decodeUTF16(body, bigEndian: true)
            case .utf16LittleEndian: return try decodeUTF16(body, bigEndian: false)
            case .utf32BigEndian: return try decodeUTF32(body, bigEndian: true)
            case .utf32LittleEndian: return try decodeUTF32(body, bigEndian: false)
            default: return String(decoding: body, as: UTF8.self)
            }
        }

        /// The byte-to-scalar mapping for a single-byte encoding, or nil for the
        /// Unicode transformation formats.
        static func singleByteMap(_ encoding: InputEncoding) -> ((UInt8) -> Unicode.Scalar)? {
            singleByteMaps[encoding]
        }

        private static let singleByteMaps: [InputEncoding: @Sendable (UInt8) -> Unicode.Scalar] = [
            .latin1: { Unicode.Scalar($0) },
            .windows1252: windows1252Scalar,
            .windows1254: SingleByte.windows1254,
            .latin2: SingleByte.iso8859_2,
            .latin3: SingleByte.iso8859_3,
            .latin4: SingleByte.iso8859_4,
            .greek: SingleByte.iso8859_7,
            .latin7: SingleByte.iso8859_13,
            .latinCyrillic: SingleByte.iso8859_5,
            .latin5: SingleByte.iso8859_9,
            .latin9: SingleByte.iso8859_15,
        ]

        private static func decodeUTF16(_ bytes: ArraySlice<UInt8>, bigEndian: Bool) throws -> String {
            guard bytes.count.isMultiple(of: 2) else {
                throw PureXML.Parsing.ParseError.malformedEncoding
            }
            var units: [UInt16] = []
            units.reserveCapacity(bytes.count / 2)
            var iterator = bytes.makeIterator()
            while let high = iterator.next(), let low = iterator.next() {
                let first = UInt16(high)
                let second = UInt16(low)
                units.append(bigEndian ? (first << 8 | second) : (second << 8 | first))
            }
            return String(decoding: units, as: UTF16.self)
        }

        private static func decodeUTF32(_ bytes: ArraySlice<UInt8>, bigEndian: Bool) throws -> String {
            guard bytes.count.isMultiple(of: 4) else {
                throw PureXML.Parsing.ParseError.malformedEncoding
            }
            let array = Array(bytes)
            var scalars = String.UnicodeScalarView()
            var index = 0
            while index + 4 <= array.count {
                let quad = array[index ..< index + 4]
                let value = (bigEndian ? AnySequence(quad) : AnySequence(quad.reversed()))
                    .reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                scalars.append(Unicode.Scalar(value) ?? "\u{FFFD}")
                index += 4
            }
            return String(scalars)
        }

        /// Reads the `encoding` pseudo-attribute from an XML declaration that is
        /// ASCII-compatible at the front (UTF-8 or a single-byte encoding).
        static func declaredEncoding(in bytes: [UInt8]) -> InputEncoding? {
            let header = Array(bytes.prefix(256))
            guard header.starts(with: Array("<?xml".utf8)) else { return nil }
            let limit = header.firstIndex(of: 0x3E) ?? header.count // ">"
            let scan = Array(header[..<limit])
            guard let position = indexOfSubsequence(Array("encoding".utf8), in: scan) else { return nil }
            var index = position + 8
            while index < scan.count, scan[index] != 0x22, scan[index] != 0x27 {
                index += 1
            }
            guard index < scan.count else { return nil }
            let quote = scan[index]
            index += 1
            var name: [UInt8] = []
            while index < scan.count, scan[index] != quote {
                name.append(scan[index])
                index += 1
            }
            return encodingByName[String(decoding: name, as: UTF8.self).lowercased()]
        }

        /// The declared encoding names PureXML recognizes, mapped to their encoding.
        private static let encodingByName: [String: InputEncoding] = [
            "utf-8": .utf8, "utf8": .utf8, "us-ascii": .utf8, "ascii": .utf8,
            "iso-8859-1": .latin1, "latin1": .latin1, "latin-1": .latin1, "l1": .latin1,
            "windows-1252": .windows1252, "cp1252": .windows1252, "cp-1252": .windows1252,
            "windows-1254": .windows1254, "cp1254": .windows1254,
            "iso-8859-2": .latin2, "iso8859-2": .latin2, "latin2": .latin2, "latin-2": .latin2, "l2": .latin2,
            "iso-8859-3": .latin3, "iso8859-3": .latin3, "latin3": .latin3, "latin-3": .latin3, "l3": .latin3,
            "iso-8859-4": .latin4, "iso8859-4": .latin4, "latin4": .latin4, "latin-4": .latin4, "l4": .latin4,
            "iso-8859-7": .greek, "iso8859-7": .greek, "greek": .greek,
            "iso-8859-13": .latin7, "iso8859-13": .latin7, "latin7": .latin7, "latin-7": .latin7, "l7": .latin7,
            "iso-8859-5": .latinCyrillic, "iso8859-5": .latinCyrillic, "cyrillic": .latinCyrillic,
            "iso-8859-9": .latin5, "iso8859-9": .latin5, "latin5": .latin5, "latin-5": .latin5, "l5": .latin5,
            "iso-8859-15": .latin9, "iso8859-15": .latin9, "latin9": .latin9, "latin-9": .latin9, "l9": .latin9,
        ]

        private static func indexOfSubsequence(_ needle: [UInt8], in haystack: [UInt8]) -> Int? {
            guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
            for start in 0 ... (haystack.count - needle.count) where Array(haystack[start ..< start + needle.count]) == needle {
                return start
            }
            return nil
        }

        /// Maps a Windows-1252 byte to its Unicode scalar. The 0x80...0x9F range
        /// is the published CP1252 table; everything else is ISO-8859-1.
        static func windows1252Scalar(_ byte: UInt8) -> Unicode.Scalar {
            guard (0x80 ... 0x9F).contains(byte) else { return Unicode.Scalar(byte) }
            let high: [UInt32] = [
                0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
                0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
                0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
                0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
            ]
            return Unicode.Scalar(high[Int(byte - 0x80)]) ?? "\u{FFFD}"
        }
    }
}
