/// The bulk byte-run scanners, split into their own file so `Reader`'s primary
/// type body and `Reader.swift` both stay under the length caps. They consume
/// plain ASCII runs of content or attribute-value text directly from the owned
/// storage (the common case in any real document) and hand subtle bytes back to
/// the Character path. Both engage only when the lookahead buffer is empty, read
/// the cursor through `Reader`'s `private(set)` accessors, and commit their
/// position deltas through `advanceByteRun` so all cursor mutation stays in
/// `Reader.swift`.
extension PureXML.Parsing.Reader {
    /// Bulk-scans character data in byte mode: consumes and returns the longest
    /// upcoming run of plain ASCII content bytes (no '<', no carriage return, no
    /// "]]" pair, every byte a valid XML character), or nil when the fast path
    /// does not apply. Anything subtle, an entity boundary aside ('&' is plain
    /// content here, noted via `sawAmpersand`), is left for the Character path so
    /// error marks stay exact. Returns nil rather than an empty run so callers
    /// can alternate with the slow loop.
    mutating func contentRunBytes(sawAmpersand: inout Bool) -> String? {
        guard buffer.isEmpty, pendingRaw == nil, let storage else { return nil }
        let pointer = storage.pointer
        let count = storage.count
        // A run never contains ']', so "]]>" can only straddle the boundary where
        // the slow path consumed "]]" and the run would begin with '>': leave a
        // leading '>' to the slow path and its cdataCloseInContent check (W3C
        // ibm14n01).
        if byteIndex < count, pointer[byteIndex] == 0x3E { return nil }
        var index = byteIndex
        var newlines = 0
        var lastLineStart = -1
        while index < count {
            let byte = pointer[index]
            if byte == 0x3C { break } // '<'
            // Valid plain ASCII content only; CR, ']' and non-ASCII go to the
            // character path.
            guard byte < 0x80, byte != 0x0D, byte != 0x5D,
                  byte >= 0x20 || byte == 0x09 || byte == 0x0A
            else {
                if index == byteIndex { return nil }
                break
            }
            if byte == 0x0A {
                newlines += 1
                lastLineStart = index
            } else if byte == 0x26 {
                sawAmpersand = true
            }
            index += 1
        }
        guard index > byteIndex else { return nil }
        let run = String(decoding: UnsafeBufferPointer(start: pointer + byteIndex, count: index - byteIndex), as: UTF8.self)
        advanceByteRun(to: index, length: index - byteIndex, newlines: newlines, lastLineStart: lastLineStart)
        return run
    }

    /// Bulk-scans an attribute value in byte mode: consumes and returns the
    /// longest upcoming run of plain ASCII value bytes, stopping at the closing
    /// `quote`, a raw '<', a carriage return (2.11 folding then 3.3.3
    /// normalization must run on the Character path), a control character, or a
    /// non-ASCII byte. Tab and line feed inside the run normalize to a single
    /// space per 3.3.3; '&' stays raw for later reference decoding and is noted
    /// via `sawAmpersand`. Returns nil when the fast path does not apply or the
    /// run would be empty, so callers alternate with the slow loop.
    mutating func attributeRunBytes(quote: UInt8, sawAmpersand: inout Bool) -> String? {
        guard buffer.isEmpty, pendingRaw == nil, let storage else { return nil }
        let pointer = storage.pointer
        let count = storage.count
        var index = byteIndex
        var newlines = 0
        var lastLineStart = -1
        var needsTransform = false
        scan: while index < count {
            switch pointer[index] {
            case quote, 0x3C, 0x80...: break scan
            case 0x0A: needsTransform = true
                newlines += 1
                lastLineStart = index
            case 0x09: needsTransform = true
            case 0x26: sawAmpersand = true
            case ..<0x20: break scan
            default: break
            }
            index += 1
        }
        guard index > byteIndex else { return nil }
        let length = index - byteIndex
        let run = attributeRunString(pointer, from: byteIndex, length: length, transform: needsTransform)
        advanceByteRun(to: index, length: length, newlines: newlines, lastLineStart: lastLineStart)
        return run
    }

    /// Builds the value string for an attribute byte run, applying the 3.3.3
    /// tab/line-feed-to-space normalization only when the run contained one.
    private func attributeRunString(_ pointer: UnsafePointer<UInt8>, from start: Int, length: Int, transform: Bool) -> String {
        guard transform else {
            return String(decoding: UnsafeBufferPointer(start: pointer + start, count: length), as: UTF8.self)
        }
        var bytes = [UInt8](repeating: 0, count: length)
        for position in 0 ..< length {
            let byte = pointer[start + position]
            bytes[position] = (byte == 0x09 || byte == 0x0A) ? 0x20 : byte
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
