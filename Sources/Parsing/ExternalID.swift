public extension PureXML.Parsing {
    /// An external identifier declared in a DTD: a required system identifier
    /// (a URI or path) and an optional public identifier. It appears on the
    /// `<!DOCTYPE>` external subset and on external entity declarations
    /// (`<!ENTITY name SYSTEM "...">` / `PUBLIC "..." "...">`).
    ///
    /// PureXML never dereferences an external identifier itself: no filesystem,
    /// no network. It is handed to an injected ``EntityResolver`` only when the
    /// caller supplies one, so the default posture keeps XXE closed.
    struct ExternalID: Equatable, Sendable {
        /// The public identifier (the `PUBLIC` literal), or nil for a `SYSTEM`
        /// identifier.
        public var publicID: String?
        /// The system identifier (the URI or path literal).
        public var systemID: String

        public init(publicID: String? = nil, systemID: String) {
            self.publicID = publicID
            self.systemID = systemID
        }
    }
}
