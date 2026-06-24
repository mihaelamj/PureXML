public extension PureXML.Parsing {
    /// Character classification per the XML 1.0 (Fifth Edition) grammar, the
    /// single source of truth for what bytes are legal where. Predicates operate
    /// on Unicode scalars, since the grammar productions are defined over code
    /// points, not graphemes.
    enum XMLCharacter {
        /// `S`: white space (space, tab, carriage return, line feed).
        public static func isWhitespace(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.value {
            case 0x20, 0x09, 0x0D, 0x0A: true
            default: false
            }
        }

        /// `Char`: any legal XML character.
        public static func isChar(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.value {
            case 0x09, 0x0A, 0x0D,
                 0x20 ... 0xD7FF,
                 0xE000 ... 0xFFFD,
                 0x10000 ... 0x10FFFF:
                true
            default:
                false
            }
        }

        /// `NameStartChar`: the first character of a name.
        public static func isNameStart(_ scalar: Unicode.Scalar) -> Bool {
            switch scalar.value {
            case 0x3A, // ":"
                 0x41 ... 0x5A, // A-Z
                 0x5F, // "_"
                 0x61 ... 0x7A, // a-z
                 0xC0 ... 0xD6,
                 0xD8 ... 0xF6,
                 0xF8 ... 0x2FF,
                 0x370 ... 0x37D,
                 0x37F ... 0x1FFF,
                 0x200C ... 0x200D,
                 0x2070 ... 0x218F,
                 0x2C00 ... 0x2FEF,
                 0x3001 ... 0xD7FF,
                 0xF900 ... 0xFDCF,
                 0xFDF0 ... 0xFFFD,
                 0x10000 ... 0xEFFFF:
                true
            default:
                false
            }
        }

        /// The ASCII subset of `NameStartChar`, tested on a raw byte for the
        /// parser's byte-level fast path. A non-ASCII name-start (byte >= 0x80)
        /// is left to the scalar predicate via the Character scanner.
        static func isASCIINameStart(_ byte: UInt8) -> Bool {
            switch byte {
            case 0x3A, 0x41 ... 0x5A, 0x5F, 0x61 ... 0x7A: true
            default: false
            }
        }

        /// The ASCII subset of `NameChar` (after the first), on a raw byte.
        static func isASCIINameChar(_ byte: UInt8) -> Bool {
            isASCIINameStart(byte) || (byte >= 0x30 && byte <= 0x39) || byte == 0x2D || byte == 0x2E
        }

        /// `NameChar`: a name character after the first.
        public static func isNameChar(_ scalar: Unicode.Scalar) -> Bool {
            if isNameStart(scalar) { return true }
            switch scalar.value {
            case 0x2D, // "-"
                 0x2E, // "."
                 0x30 ... 0x39, // 0-9
                 0xB7,
                 0x300 ... 0x36F,
                 0x203F ... 0x2040:
                return true
            default:
                return false
            }
        }

        /// `Name`: a NameStartChar followed by zero or more NameChar.
        public static func isValidName(_ name: String) -> Bool {
            var scalars = name.unicodeScalars.makeIterator()
            guard let first = scalars.next(), isNameStart(first) else { return false }
            while let scalar = scalars.next() {
                if !isNameChar(scalar) { return false }
            }
            return true
        }

        /// `Nmtoken`: one or more NameChar (no name-start requirement).
        public static func isNmtoken(_ token: String) -> Bool {
            let scalars = token.unicodeScalars
            guard !scalars.isEmpty else { return false }
            return scalars.allSatisfy(isNameChar)
        }
    }
}
