public extension PureXML.Parsing {
    /// An injected resolver for external entities and the external DTD subset.
    ///
    /// PureXML never reads a file or opens a socket on its own. By default no
    /// resolver is wired in (``refusing``), so every external reference is
    /// refused: an external general entity then fails as undefined when used, and
    /// an external subset is simply not loaded. This is the XXE-closed posture.
    ///
    /// To opt in, supply closures, for example mapping a known set of system
    /// identifiers to in-memory replacement text. A closure returns nil to refuse
    /// an individual reference. It is a struct of closures rather than a protocol
    /// so it composes with the value-typed parsing API and stays `Sendable`.
    struct EntityResolver: Sendable {
        /// Resolves an external general entity to its replacement text, given the
        /// entity name and its external identifier. Returns nil to refuse, which
        /// leaves the entity undefined (a reference to it then errors).
        public var resolveEntity: @Sendable (_ name: String, _ id: ExternalID) -> String?
        /// Resolves the external DTD subset (or an external identifier referenced
        /// from a `<!DOCTYPE>`) to its declaration text. Returns nil to refuse,
        /// which leaves the external subset unread.
        public var resolveExternalSubset: @Sendable (_ id: ExternalID) -> String?

        public init(
            resolveEntity: @escaping @Sendable (_ name: String, _ id: ExternalID) -> String? = { _, _ in nil },
            resolveExternalSubset: @escaping @Sendable (_ id: ExternalID) -> String? = { _ in nil },
        ) {
            self.resolveEntity = resolveEntity
            self.resolveExternalSubset = resolveExternalSubset
        }

        /// The default resolver: refuses every external reference, keeping XXE
        /// and external-DTD fetching closed.
        public static let refusing = EntityResolver()
    }
}
