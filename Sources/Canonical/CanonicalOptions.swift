public extension PureXML.Canonical {
    /// Whether to render every in-scope namespace (inclusive C14N) or only the
    /// namespaces an element and its attributes actually use (exclusive C14N).
    enum Mode: Equatable, Sendable {
        case inclusive
        case exclusive
    }

    /// Options for canonicalization. The default is inclusive C14N without
    /// comments, matching the common XML-signature use.
    ///
    /// For whole-document and whole-subtree canonicalization, C14N 1.0 and 1.1
    /// produce identical output (their differences only affect `xml:*` attribute
    /// inheritance into selected document subsets), so this single inclusive mode
    /// covers both.
    struct Options: Equatable, Sendable {
        public var mode: Mode
        public var includeComments: Bool
        /// Prefixes always rendered in exclusive mode even when not visibly used
        /// (the `InclusiveNamespaces` PrefixList).
        public var inclusiveNamespacePrefixes: [String]

        public init(
            mode: Mode = .inclusive,
            includeComments: Bool = false,
            inclusiveNamespacePrefixes: [String] = [],
        ) {
            self.mode = mode
            self.includeComments = includeComments
            self.inclusiveNamespacePrefixes = inclusiveNamespacePrefixes
        }

        /// Inclusive C14N without comments.
        public static let inclusive = Options(mode: .inclusive)
        /// Exclusive C14N without comments.
        public static let exclusive = Options(mode: .exclusive)
    }
}
