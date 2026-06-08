public extension PureXML.Parsing {
    /// A character encoding PureXML can decode from raw bytes. Covers the
    /// Unicode transformation formats plus the common single-byte encodings
    /// (ISO-8859-1 and Windows-1252), toward libxml2 encoding parity.
    enum InputEncoding: String, Equatable, Sendable {
        case utf8
        case utf16BigEndian
        case utf16LittleEndian
        case utf32BigEndian
        case utf32LittleEndian
        case latin1
        case windows1252

        /// Detects the encoding from the leading bytes, following the XML sniff
        /// order: a byte-order mark first, then the `<?` byte pattern of the XML
        /// declaration, defaulting to UTF-8. Single-byte encodings are not
        /// detectable from bytes alone; they come from the declared encoding name.
        public static func detect(_ bytes: [UInt8]) -> InputEncoding {
            detectWithBOM(bytes).encoding
        }

        /// Detects the encoding and the length of any byte-order mark to strip.
        static func detectWithBOM(_ bytes: [UInt8]) -> (encoding: InputEncoding, bomLength: Int) {
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
                return (.utf8, 3)
            }
            // UTF-32 marks are four bytes and must be checked before UTF-16, since
            // the UTF-32LE mark begins with the UTF-16LE mark.
            if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
                return (.utf32BigEndian, 4)
            }
            if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) {
                return (.utf32LittleEndian, 4)
            }
            if bytes.starts(with: [0xFE, 0xFF]) {
                return (.utf16BigEndian, 2)
            }
            if bytes.starts(with: [0xFF, 0xFE]) {
                return (.utf16LittleEndian, 2)
            }
            // No BOM: sniff the "<?" byte pattern of an XML declaration.
            if bytes.starts(with: [0x00, 0x00, 0x00, 0x3C]) {
                return (.utf32BigEndian, 0)
            }
            if bytes.starts(with: [0x3C, 0x00, 0x00, 0x00]) {
                return (.utf32LittleEndian, 0)
            }
            if bytes.starts(with: [0x00, 0x3C, 0x00, 0x3F]) {
                return (.utf16BigEndian, 0)
            }
            if bytes.starts(with: [0x3C, 0x00, 0x3F, 0x00]) {
                return (.utf16LittleEndian, 0)
            }
            return (.utf8, 0)
        }
    }
}
