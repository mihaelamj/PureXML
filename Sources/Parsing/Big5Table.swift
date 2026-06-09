extension PureXML.Parsing.ByteDecoder {
    /// The Big5 index (Traditional Chinese plus the HKSCS extensions, including
    /// the astral CJK ideographs), assembled from the vendored parts. Indexed by
    /// `pointer - 942`, the first populated pointer; a `0` entry is an unmapped
    /// slot. Vendored verbatim from the WHATWG `index-big5.txt`; reproduce from
    /// that file rather than hand-editing.
    static let big5: [UInt32] = big5Part1 + big5Part2 + big5Part3 + big5Part4 + big5Part5 + big5Part6

    /// The first pointer populated in the Big5 index.
    static let big5Base = 942
}
