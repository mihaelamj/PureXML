public extension PureXML.Parsing {
    /// A character encoding PureXML can decode from raw bytes. XML processors are
    /// required to support UTF-8 and UTF-16; those are covered here. Other declared
    /// encodings are out of scope (and reported as malformed rather than guessed).
    enum InputEncoding: String, Equatable, Sendable {
        case utf8
        case utf16BigEndian
        case utf16LittleEndian

        /// Detects the encoding from the leading bytes, following the XML sniff
        /// order: a byte-order mark first, then the `<?` byte pattern of the XML
        /// declaration, defaulting to UTF-8 when neither is present.
        public static func detect(_ bytes: [UInt8]) -> InputEncoding {
            detectWithBOM(bytes).encoding
        }

        /// Detects the encoding and the length of any byte-order mark to strip.
        static func detectWithBOM(_ bytes: [UInt8]) -> (encoding: InputEncoding, bomLength: Int) {
            if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
                return (.utf8, 3)
            }
            if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF {
                return (.utf16BigEndian, 2)
            }
            if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xFE {
                return (.utf16LittleEndian, 2)
            }
            // No BOM: sniff the "<?" pattern of an XML declaration.
            if bytes.count >= 4, bytes[0] == 0x00, bytes[1] == 0x3C, bytes[2] == 0x00, bytes[3] == 0x3F {
                return (.utf16BigEndian, 0)
            }
            if bytes.count >= 4, bytes[0] == 0x3C, bytes[1] == 0x00, bytes[2] == 0x3F, bytes[3] == 0x00 {
                return (.utf16LittleEndian, 0)
            }
            return (.utf8, 0)
        }
    }
}
