public extension PureXML.Parsing {
    /// Encodes a Unicode string into bytes for output, the inverse of
    /// ``ByteDecoder``. Covers the Unicode transformation formats and the
    /// single-byte legacy families (built by inverting the same vendored
    /// to-Unicode tables, so no new data is introduced). A scalar the target
    /// encoding cannot represent is written as a decimal numeric character
    /// reference, matching libxml2's save behavior.
    enum ByteEncoder {
        /// Whether `encoding` can be produced by ``encode(_:as:)``.
        public static func supports(_ encoding: InputEncoding) -> Bool {
            switch encoding {
            case .utf8, .utf16BigEndian, .utf16LittleEndian, .utf32BigEndian, .utf32LittleEndian:
                true
            default:
                ByteDecoder.singleByteMap(encoding) != nil
            }
        }

        /// The bytes of `string` in `encoding`. Unrepresentable scalars become
        /// `&#NNNN;` character references (whose own bytes are ASCII, encodable
        /// everywhere). Returns the UTF-8 bytes for an unsupported encoding.
        public static func encode(_ string: String, as encoding: InputEncoding) -> [UInt8] {
            switch encoding {
            case .utf8: Array(string.utf8)
            case .utf16BigEndian: utf16(string, bigEndian: true)
            case .utf16LittleEndian: utf16(string, bigEndian: false)
            case .utf32BigEndian: utf32(string, bigEndian: true)
            case .utf32LittleEndian: utf32(string, bigEndian: false)
            default: singleByte(string, encoding: encoding)
            }
        }

        /// The byte-order mark for `encoding` (empty for the byte-oriented ones).
        public static func byteOrderMark(_ encoding: InputEncoding) -> [UInt8] {
            switch encoding {
            case .utf16BigEndian: [0xFE, 0xFF]
            case .utf16LittleEndian: [0xFF, 0xFE]
            case .utf32BigEndian: [0x00, 0x00, 0xFE, 0xFF]
            case .utf32LittleEndian: [0xFF, 0xFE, 0x00, 0x00]
            default: []
            }
        }

        // MARK: Unicode transformation formats

        private static func utf16(_ string: String, bigEndian: Bool) -> [UInt8] {
            var bytes: [UInt8] = []
            for unit in string.utf16 {
                let pair: [UInt8] = [UInt8(unit >> 8), UInt8(unit & 0xFF)]
                bytes.append(contentsOf: bigEndian ? pair : pair.reversed())
            }
            return bytes
        }

        private static func utf32(_ string: String, bigEndian: Bool) -> [UInt8] {
            var bytes: [UInt8] = []
            for scalar in string.unicodeScalars {
                let value = scalar.value
                let quad: [UInt8] = [
                    UInt8(value >> 24 & 0xFF),
                    UInt8(value >> 16 & 0xFF),
                    UInt8(value >> 8 & 0xFF),
                    UInt8(value & 0xFF),
                ]
                bytes.append(contentsOf: bigEndian ? quad : quad.reversed())
            }
            return bytes
        }

        // MARK: Single-byte families

        private static func singleByte(_ string: String, encoding: InputEncoding) -> [UInt8] {
            guard let inverse = singleByteInverse(encoding) else { return Array(string.utf8) }
            var bytes: [UInt8] = []
            for scalar in string.unicodeScalars {
                if let byte = inverse[scalar.value] {
                    bytes.append(byte)
                } else {
                    bytes.append(contentsOf: Array("&#\(scalar.value);".utf8))
                }
            }
            return bytes
        }

        /// The scalar-to-byte map for a single-byte encoding, inverted from its
        /// forward table. The lowest byte wins a collision, and the `0xFFFD`
        /// sentinel for an unmapped byte is skipped.
        private static func singleByteInverse(_ encoding: InputEncoding) -> [UInt32: UInt8]? {
            guard let forward = ByteDecoder.singleByteMap(encoding) else { return nil }
            var map: [UInt32: UInt8] = [:]
            for byte in UInt8.min ... UInt8.max {
                let value = forward(byte).value
                if value == 0xFFFD { continue }
                if map[value] == nil { map[value] = byte }
            }
            return map
        }

        // MARK: Declaration names

        /// The canonical encoding name to write in the XML declaration.
        public static func canonicalName(_ encoding: InputEncoding) -> String {
            canonicalNames[encoding] ?? "UTF-8"
        }

        private static let canonicalNames: [InputEncoding: String] = [
            .utf8: "UTF-8",
            .utf16BigEndian: "UTF-16", .utf16LittleEndian: "UTF-16",
            .utf32BigEndian: "UTF-32", .utf32LittleEndian: "UTF-32",
            .latin1: "ISO-8859-1", .latin2: "ISO-8859-2", .latin3: "ISO-8859-3",
            .latin4: "ISO-8859-4", .latinCyrillic: "ISO-8859-5", .arabic: "ISO-8859-6",
            .greek: "ISO-8859-7", .hebrew: "ISO-8859-8", .latin5: "ISO-8859-9",
            .latin6: "ISO-8859-10", .thai: "ISO-8859-11", .latin7: "ISO-8859-13",
            .latin8: "ISO-8859-14", .latin9: "ISO-8859-15", .latin10: "ISO-8859-16",
            .windows1250: "windows-1250", .windows1251: "windows-1251", .windows1252: "windows-1252",
            .windows1253: "windows-1253", .windows1254: "windows-1254", .windows1255: "windows-1255",
            .windows1256: "windows-1256", .windows1257: "windows-1257", .windows1258: "windows-1258",
            .koi8r: "KOI8-R", .koi8u: "KOI8-U",
        ]
    }
}
