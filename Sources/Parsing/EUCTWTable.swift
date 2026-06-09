extension PureXML.Parsing.ByteDecoder {
    /// CNS 11643 plane 1 and plane 2, the planes that carry essentially all
    /// real-world EUC-TW text, indexed by `(b1-0xA1)*94 + (b2-0xA1)`. A `0` entry
    /// is unmapped. Vendored from the ICU `euc-tw-2014` mapping (private-use
    /// fallbacks dropped); reproduce from that file. Planes 3-15 are not vendored.
    static let eucTWPlane1: [UInt32] = eucTWPlane1Part1 + eucTWPlane1Part2 + eucTWPlane1Part3
    static let eucTWPlane2: [UInt32] = eucTWPlane2Part1 + eucTWPlane2Part2 + eucTWPlane2Part3
}
