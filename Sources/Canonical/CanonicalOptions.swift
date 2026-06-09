public extension PureXML.Canonical {
    /// Whether to render every in-scope namespace (inclusive C14N) or only the
    /// namespaces an element and its attributes actually use (exclusive C14N).
    enum Mode: Equatable, Sendable {
        case inclusive
        case exclusive
    }

    /// The Canonical XML 2.0 `PrefixRewrite` parameter: how namespace prefixes
    /// are spelled in the output.
    enum PrefixRewrite: Equatable, Sendable {
        /// Keep each declaration's original prefix (C14N 1.0/1.1 behavior).
        case retain
        /// Rewrite every prefix to a sequential canonical name (`n0`, `n1`, ...)
        /// assigned in document order of first use, so two documents that differ
        /// only in how they spell their prefixes canonicalize to the same bytes.
        /// The reserved `xml` prefix is never rewritten.
        case sequential
    }

    /// A Canonical XML 2.0 `QNameAware` label: an attribute (or element) whose
    /// textual value is a QName, so its prefix is rewritten alongside the
    /// structural prefixes under ``PrefixRewrite/sequential``.
    struct QNameAwareLabel: Equatable, Sendable {
        /// The namespace URI of the labelled attribute or element (empty for none).
        public let namespaceURI: String
        /// The local name of the labelled attribute or element.
        public let localName: String
        /// Whether the label names an element (its text content is the QName)
        /// rather than an attribute (its value is the QName).
        public let isElement: Bool

        public init(namespaceURI: String = "", localName: String, isElement: Bool = false) {
            self.namespaceURI = namespaceURI
            self.localName = localName
            self.isElement = isElement
        }
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
        /// The Canonical XML 2.0 `TrimTextNodes` parameter: when true, leading and
        /// trailing whitespace is stripped from each text node, and a text node
        /// that is all whitespace is dropped.
        public var trimTextNodes: Bool
        /// The Canonical XML 2.0 `PrefixRewrite` parameter (default ``PrefixRewrite/retain``).
        public var prefixRewrite: PrefixRewrite
        /// The Canonical XML 2.0 `QNameAware` labels: attributes or elements whose
        /// value is a QName, so its prefix is rewritten under sequential rewrite.
        public var qnameAwareLabels: [QNameAwareLabel]

        public init(
            mode: Mode = .inclusive,
            includeComments: Bool = false,
            inclusiveNamespacePrefixes: [String] = [],
            trimTextNodes: Bool = false,
            prefixRewrite: PrefixRewrite = .retain,
            qnameAwareLabels: [QNameAwareLabel] = [],
        ) {
            self.mode = mode
            self.includeComments = includeComments
            self.inclusiveNamespacePrefixes = inclusiveNamespacePrefixes
            self.trimTextNodes = trimTextNodes
            self.prefixRewrite = prefixRewrite
            self.qnameAwareLabels = qnameAwareLabels
        }

        /// Inclusive C14N without comments.
        public static let inclusive = Options(mode: .inclusive)
        /// Exclusive C14N without comments.
        public static let exclusive = Options(mode: .exclusive)
        /// Canonical XML 2.0 with text-node trimming enabled.
        public static let canonical2 = Options(mode: .inclusive, trimTextNodes: true)
    }
}
