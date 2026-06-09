extension PureXML.Parsing.ByteDecoder {
    /// The ISO-2022-JP decoder (the WHATWG `iso-2022-jp` algorithm). Unlike the
    /// other CJK encodings this one is stateful: escape sequences switch between
    /// ASCII, JIS X 0201 Roman, JIS X 0201 katakana, and the JIS X 0208 plane,
    /// which is resolved through the shared `jis0208` table (no new data).
    enum ISO2022JP {
        static func decode(_ bytes: ArraySlice<UInt8>) -> String {
            var scalars = String.UnicodeScalarView()
            var mode: ISO2022JPMode = .ascii
            var lead: UInt8?
            let array = Array(bytes)
            var index = 0
            while index < array.count {
                let byte = array[index]
                index += 1
                if byte == 0x1B {
                    mode = applyEscape(array, &index, into: &scalars) ?? mode
                    lead = nil
                    continue
                }
                decodeByte(byte, mode: mode, lead: &lead, into: &scalars)
            }
            if lead != nil { scalars.append("\u{FFFD}") }
            return String(scalars)
        }

        /// Reads the bytes after an escape and returns the new mode, or nil (with a
        /// replacement emitted) for an unrecognized sequence.
        private static func applyEscape(_ array: [UInt8], _ index: inout Int, into scalars: inout String.UnicodeScalarView) -> ISO2022JPMode? {
            guard index < array.count else { scalars.append("\u{FFFD}")
                return nil
            }
            let first = array[index]
            index += 1
            guard index < array.count else { scalars.append("\u{FFFD}")
                return nil
            }
            let second = array[index]
            index += 1
            switch (first, second) {
            case (0x28, 0x42): return .ascii // ESC ( B
            case (0x28, 0x4A): return .roman // ESC ( J
            case (0x28, 0x49): return .katakana // ESC ( I
            case (0x24, 0x40), (0x24, 0x42): return .jis0208 // ESC $ @ / ESC $ B
            default:
                scalars.append("\u{FFFD}")
                return nil
            }
        }

        private static func decodeByte(_ byte: UInt8, mode: ISO2022JPMode, lead: inout UInt8?, into scalars: inout String.UnicodeScalarView) {
            switch mode {
            case .ascii:
                scalars.append(byte <= 0x7F ? Unicode.Scalar(byte) : "\u{FFFD}")
            case .roman:
                switch byte {
                case 0x5C: scalars.append("\u{00A5}") // yen
                case 0x7E: scalars.append("\u{203E}") // overline
                case 0 ... 0x7F: scalars.append(Unicode.Scalar(byte))
                default: scalars.append("\u{FFFD}")
                }
            case .katakana:
                if (0x21 ... 0x5F).contains(byte) {
                    scalars.append(Unicode.Scalar(0xFF61 + UInt32(byte) - 0x21) ?? "\u{FFFD}")
                } else {
                    scalars.append("\u{FFFD}")
                }
            case .jis0208:
                decodeJIS0208(byte, lead: &lead, into: &scalars)
            }
        }

        private static func decodeJIS0208(_ byte: UInt8, lead: inout UInt8?, into scalars: inout String.UnicodeScalarView) {
            guard let first = lead else {
                if (0x21 ... 0x7E).contains(byte) {
                    lead = byte
                } else if byte == 0x0A || byte == 0x0D {
                    scalars.append(Unicode.Scalar(byte))
                } else {
                    scalars.append("\u{FFFD}")
                }
                return
            }
            lead = nil
            guard (0x21 ... 0x7E).contains(first), (0x21 ... 0x7E).contains(byte) else {
                scalars.append("\u{FFFD}")
                return
            }
            let pointer = (Int(first) - 0x21) * 94 + Int(byte) - 0x21
            if pointer >= 0, pointer < jis0208.count, jis0208[pointer] != 0xFFFF {
                scalars.append(Unicode.Scalar(UInt32(jis0208[pointer])) ?? "\u{FFFD}")
            } else {
                scalars.append("\u{FFFD}")
            }
        }
    }
}

/// The active character set while decoding ISO-2022-JP, switched by escape
/// sequences.
private enum ISO2022JPMode {
    case ascii
    case roman
    case katakana
    case jis0208
}
