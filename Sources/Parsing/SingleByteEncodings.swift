extension PureXML.Parsing.ByteDecoder {
    /// To-Unicode mappings for the single-byte legacy encodings. Each maps one
    /// byte to its Unicode scalar; bytes `0x00`-`0x7F` are ASCII in every case.
    /// A few encodings are expressed exactly (ISO-8859-1 with substitutions, or a
    /// contiguous block); the rest are vendored verbatim from the authoritative
    /// `unicode.org` mapping files (see `SingleByteTables.swift`).
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

        /// The table-driven encodings, vendored from the Unicode mapping files.
        static func iso8859_2(_ byte: UInt8) -> Unicode.Scalar {
            upperHalf(byte, latin2Upper)
        }

        static func iso8859_3(_ byte: UInt8) -> Unicode.Scalar {
            upperHalf(byte, latin3Upper)
        }

        static func iso8859_4(_ byte: UInt8) -> Unicode.Scalar {
            upperHalf(byte, latin4Upper)
        }

        static func iso8859_7(_ byte: UInt8) -> Unicode.Scalar {
            upperHalf(byte, greekUpper)
        }

        static func iso8859_13(_ byte: UInt8) -> Unicode.Scalar {
            upperHalf(byte, latin7Upper)
        }

        static func iso8859_6(_ byte: UInt8) -> Unicode.Scalar {
            upperHalf(byte, arabicUpper)
        }

        static func iso8859_8(_ byte: UInt8) -> Unicode.Scalar {
            upperHalf(byte, hebrewUpper)
        }

        static func iso8859_10(_ byte: UInt8) -> Unicode.Scalar {
            upperHalf(byte, latin6Upper)
        }

        static func iso8859_14(_ byte: UInt8) -> Unicode.Scalar {
            upperHalf(byte, latin8Upper)
        }

        static func iso8859_16(_ byte: UInt8) -> Unicode.Scalar {
            upperHalf(byte, latin10Upper)
        }

        static func iso8859_11(_ byte: UInt8) -> Unicode.Scalar {
            upperHalf(byte, thaiUpper)
        }

        static func windows1250(_ byte: UInt8) -> Unicode.Scalar {
            fullHigh(byte, windows1250High)
        }

        static func windows1251(_ byte: UInt8) -> Unicode.Scalar {
            fullHigh(byte, windows1251High)
        }

        static func windows1253(_ byte: UInt8) -> Unicode.Scalar {
            fullHigh(byte, windows1253High)
        }

        static func windows1257(_ byte: UInt8) -> Unicode.Scalar {
            fullHigh(byte, windows1257High)
        }

        static func koi8r(_ byte: UInt8) -> Unicode.Scalar {
            fullHigh(byte, koi8rHigh)
        }

        static func windows1255(_ byte: UInt8) -> Unicode.Scalar {
            fullHigh(byte, windows1255High)
        }

        static func windows1256(_ byte: UInt8) -> Unicode.Scalar {
            fullHigh(byte, windows1256High)
        }

        static func windows1258(_ byte: UInt8) -> Unicode.Scalar {
            fullHigh(byte, windows1258High)
        }

        static func koi8u(_ byte: UInt8) -> Unicode.Scalar {
            fullHigh(byte, koi8uHigh)
        }

        /// Maps a byte through a 96-entry upper-half table (`0xA0`-`0xFF`); bytes
        /// below `0xA0` are ASCII or C1 controls (identity). Used by the encodings
        /// whose upper half is vendored from the Unicode mapping files.
        static func upperHalf(_ byte: UInt8, _ table: [UInt16]) -> Unicode.Scalar {
            byte >= 0xA0 ? scalar(UInt32(table[Int(byte) - 0xA0])) : Unicode.Scalar(byte)
        }

        /// Maps a byte through a 128-entry high-half table (`0x80`-`0xFF`); bytes
        /// below `0x80` are ASCII. Used by the Windows code pages and KOI8, which
        /// remap the `0x80`-`0x9F` range too.
        static func fullHigh(_ byte: UInt8, _ table: [UInt16]) -> Unicode.Scalar {
            byte >= 0x80 ? scalar(UInt32(table[Int(byte) - 0x80])) : Unicode.Scalar(byte)
        }

        static func scalar(_ value: UInt32) -> Unicode.Scalar {
            Unicode.Scalar(value) ?? "\u{FFFD}"
        }
    }
}
