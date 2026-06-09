extension PureXML.Parsing.ByteDecoder {
    /// The EUC-TW decoder (CNS 11643). ASCII passes through; a lead in `0xA1`-`0xFE`
    /// opens a two-byte plane-1 character; `0x8E` opens a four-byte form whose
    /// second byte selects the plane (`0xA1` = plane 1, `0xA2` = plane 2). Only the
    /// real-world planes 1 and 2 are vendored; the rarely used planes 3-15 decode
    /// to the replacement character.
    enum EUCTW {
        static func decode(_ bytes: ArraySlice<UInt8>) -> String {
            var scalars = String.UnicodeScalarView()
            let array = Array(bytes)
            var index = 0
            while index < array.count {
                let byte = array[index]
                if byte <= 0x7F {
                    scalars.append(Unicode.Scalar(byte))
                    index += 1
                } else if byte == 0x8E {
                    guard index + 3 < array.count else { scalars.append("\u{FFFD}")
                        index += 1
                        continue
                    }
                    scalars.append(fourByteScalar(array[index + 1], array[index + 2], array[index + 3]) ?? "\u{FFFD}")
                    index += 4
                } else if (0xA1 ... 0xFE).contains(byte) {
                    guard index + 1 < array.count, (0xA1 ... 0xFE).contains(array[index + 1]) else {
                        scalars.append("\u{FFFD}")
                        index += 1
                        continue
                    }
                    scalars.append(planeScalar(eucTWPlane1, byte, array[index + 1]) ?? "\u{FFFD}")
                    index += 2
                } else {
                    scalars.append("\u{FFFD}")
                    index += 1
                }
            }
            return String(scalars)
        }

        /// The scalar for a `(lead, trail)` pair within `table` (a CNS plane), or nil
        /// for an out-of-range or unmapped pair.
        static func planeScalar(_ table: [UInt32], _ lead: UInt8, _ trail: UInt8) -> Unicode.Scalar? {
            guard (0xA1 ... 0xFE).contains(lead), (0xA1 ... 0xFE).contains(trail) else { return nil }
            let pointer = (Int(lead) - 0xA1) * 94 + Int(trail) - 0xA1
            guard pointer >= 0, pointer < table.count, table[pointer] != 0 else { return nil }
            return Unicode.Scalar(table[pointer])
        }

        /// The scalar for a four-byte form: the plane selector then a `(lead, trail)`
        /// pair. Planes beyond the vendored 1 and 2 return nil.
        static func fourByteScalar(_ plane: UInt8, _ lead: UInt8, _ trail: UInt8) -> Unicode.Scalar? {
            switch plane {
            case 0xA1: planeScalar(eucTWPlane1, lead, trail)
            case 0xA2: planeScalar(eucTWPlane2, lead, trail)
            default: nil
            }
        }
    }
}
