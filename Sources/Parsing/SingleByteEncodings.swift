extension PureXML.Parsing.ByteDecoder {
    /// To-Unicode mappings for the single-byte legacy encodings. Each maps one
    /// byte to its Unicode scalar; bytes `0x00`-`0x7F` are ASCII in every case.
    /// The encodings here are the ones expressible exactly as ISO-8859-1 with a
    /// few substitutions or as a contiguous block, so they carry no risk of a
    /// transcription error.
    enum SingleByte {
        /// ISO-8859-15 (Latin-9): ISO-8859-1 with the euro sign and seven other
        /// substitutions.
        static func iso8859_15(_ byte: UInt8) -> Unicode.Scalar {
            switch byte {
            case 0xA4: "\u{20AC}" // €
            case 0xA6: "\u{0160}" // Š
            case 0xA8: "\u{0161}" // š
            case 0xB4: "\u{017D}" // Ž
            case 0xB8: "\u{017E}" // ž
            case 0xBC: "\u{0152}" // Œ
            case 0xBD: "\u{0153}" // œ
            case 0xBE: "\u{0178}" // Ÿ
            default: Unicode.Scalar(byte)
            }
        }

        /// ISO-8859-9 (Latin-5, Turkish): ISO-8859-1 with six Turkish letters
        /// replacing the Icelandic ones.
        static func iso8859_9(_ byte: UInt8) -> Unicode.Scalar {
            switch byte {
            case 0xD0: "\u{011E}" // Ğ
            case 0xDD: "\u{0130}" // İ
            case 0xDE: "\u{015E}" // Ş
            case 0xF0: "\u{011F}" // ğ
            case 0xFD: "\u{0131}" // ı
            case 0xFE: "\u{015F}" // ş
            default: Unicode.Scalar(byte)
            }
        }

        /// Windows-1254 (Turkish): Windows-1252 with the same six Turkish letters
        /// as ISO-8859-9 (the only differences fall in the Latin-1 upper half).
        static func windows1254(_ byte: UInt8) -> Unicode.Scalar {
            switch byte {
            case 0xD0: "\u{011E}" // Ğ
            case 0xDD: "\u{0130}" // İ
            case 0xDE: "\u{015E}" // Ş
            case 0xF0: "\u{011F}" // ğ
            case 0xFD: "\u{0131}" // ı
            case 0xFE: "\u{015F}" // ş
            default: PureXML.Parsing.ByteDecoder.windows1252Scalar(byte)
            }
        }

        /// ISO-8859-5 (Latin/Cyrillic): the Cyrillic alphabet laid out as a
        /// contiguous block from `0xB0`, with a handful of named exceptions.
        static func iso8859_5(_ byte: UInt8) -> Unicode.Scalar {
            switch byte {
            case 0xA1 ... 0xAC: scalar(0x0401 + UInt32(byte) - 0xA1) // Ё..Ќ
            case 0xAE ... 0xAF: scalar(0x040E + UInt32(byte) - 0xAE) // Ў Џ
            case 0xB0 ... 0xEF: scalar(0x0410 + UInt32(byte) - 0xB0) // А..я
            case 0xF0: "\u{2116}" // №
            case 0xF1 ... 0xFC: scalar(0x0451 + UInt32(byte) - 0xF1) // ё..ќ
            case 0xFD: "\u{00A7}" // §
            case 0xFE ... 0xFF: scalar(0x045E + UInt32(byte) - 0xFE) // ў џ
            default: Unicode.Scalar(byte) // ASCII, C1, NBSP (0xA0), SHY (0xAD)
            }
        }

        private static func scalar(_ value: UInt32) -> Unicode.Scalar {
            Unicode.Scalar(value) ?? "\u{FFFD}"
        }
    }
}
