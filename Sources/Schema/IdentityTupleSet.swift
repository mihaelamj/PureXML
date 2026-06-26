/// A membership set for identity-constraint value tuples that detects an equal
/// tuple in (amortized) O(1) for the common case instead of scanning every
/// stored tuple, which made `unique`/`key`/`keyref` validation quadratic over a
/// wide list (one duplicate scan per target, each linear in the targets seen).
///
/// `FieldValue` equality is value-space aware (`3.0` equals `3`, `true` equals
/// `1`, a QName equals an equivalent prefix), so it cannot be hashed directly: a
/// consistent hash would have to canonicalize each value space, and the QName
/// case even depends on the other operand. Instead the set keys only the tuples
/// it can prove compare as raw strings, and keeps the exact pairwise comparison
/// for the rest, so behavior is identical to the former linear scan.
///
/// A field compares as a raw string when it is type-less (lexical equality) or
/// an atomic, lexically-compared, whitespace-preserving type (so `valueMatches`
/// reduces to `string == string`), and carries no colon that could trigger QName
/// resolution. Two such tuples are equal exactly when their raw strings match,
/// so they live in a `Set` keyed by those strings. Tuples with any value-space,
/// whitespace-collapsing, or QName-bearing field are kept verbatim and compared
/// with `==`; a raw-string query still scans them, and a value-space query scans
/// everything, so no equal pair is ever missed.
struct TupleSet {
    private var rawKeys: Set<[String]> = []
    private var unsafe: [[FieldValue?]] = []
    /// Every inserted tuple, consulted only when a value-space query must be
    /// compared against the raw-string-keyed tuples too.
    private var all: [[FieldValue?]] = []

    /// Whether a stored tuple is equal to `tuple` under `FieldValue` equality.
    func contains(_ tuple: [FieldValue?]) -> Bool {
        if let key = Self.rawKey(of: tuple) {
            return rawKeys.contains(key) || unsafe.contains { $0 == tuple }
        }
        return all.contains { $0 == tuple }
    }

    mutating func insert(_ tuple: [FieldValue?]) {
        if let key = Self.rawKey(of: tuple) {
            rawKeys.insert(key)
        } else {
            unsafe.append(tuple)
        }
        all.append(tuple)
    }

    /// The raw-string key of a tuple every one of whose fields compares as a raw
    /// string, or nil when any field needs the value-space comparison.
    private static func rawKey(of tuple: [FieldValue?]) -> [String]? {
        var key: [String] = []
        key.reserveCapacity(tuple.count)
        for field in tuple {
            guard let field, !field.string.contains(":") else { return nil }
            if let type = field.type, !type.comparesRawLexically { return nil }
            key.append(field.string)
        }
        return key
    }
}
