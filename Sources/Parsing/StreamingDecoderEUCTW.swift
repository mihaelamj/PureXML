extension PureXML.Parsing.StreamingDecoder {
    /// Streams one EUC-TW character: ASCII, a two-byte plane-1 pair, or a `0x8E`
    /// four-byte plane selector plus a pair.
    mutating func nextEUCTW() -> Character? {
        guard let lead = nextByte() else {
            finished = true
            return nil
        }
        if lead <= 0x7F { return Character(Unicode.Scalar(lead)) }
        if lead == 0x8E {
            guard let plane = nextByte(), let byte1 = nextByte(), let byte2 = nextByte() else {
                finished = true
                return Self.replacement
            }
            return PureXML.Parsing.ByteDecoder.EUCTW.fourByteScalar(plane, byte1, byte2).map(Character.init) ?? Self.replacement
        }
        guard (0xA1 ... 0xFE).contains(lead) else { return Self.replacement }
        guard let trail = nextByte() else {
            finished = true
            return Self.replacement
        }
        let table = PureXML.Parsing.ByteDecoder.eucTWPlane1
        return PureXML.Parsing.ByteDecoder.EUCTW.planeScalar(table, lead, trail).map(Character.init) ?? Self.replacement
    }
}
