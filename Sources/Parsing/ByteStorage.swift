extension PureXML.Parsing {
    /// Owned contiguous UTF-8 storage for the Reader's fast path: one copy
    /// of the input, read through an unsafe cursor with no per-byte bounds
    /// or retain traffic. The bytes come from a Swift String, so they are
    /// valid UTF-8 by construction. The pointer never escapes the parser;
    /// deallocation rides the class lifetime.
    final class ByteStorage {
        let pointer: UnsafeMutablePointer<UInt8>
        let count: Int

        init(_ bytes: [UInt8]) {
            count = bytes.count
            pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: max(count, 1))
            bytes.withUnsafeBufferPointer { buffer in
                if let base = buffer.baseAddress {
                    pointer.initialize(from: base, count: count)
                }
            }
        }

        deinit {
            pointer.deinitialize(count: count)
            pointer.deallocate()
        }
    }
}
