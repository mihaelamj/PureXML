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
        /// The URI of the entity whose text declared this identifier, when
        /// known: a relative system identifier resolves against it (RFC 3986),
        /// so nested external entities find their siblings.
        public var base: String?

        public init(publicID: String? = nil, systemID: String, base: String? = nil) {
            self.publicID = publicID
            self.systemID = systemID
            self.base = base
        }

        /// The system identifier with any base applied, ready for a resolver.
        public var resolvedSystemID: String {
            guard let base else { return systemID }
            let merged = PureXML.Canonical.Canonicalizer.resolveURI(systemID, against: base)
            // The RFC 3986 merge assumes an absolute base; when both base and
            // reference are relative paths, keep the merged path relative.
            let baseHasScheme = base.split(separator: "/", maxSplits: 1)[0].hasSuffix(":")
            if !base.hasPrefix("/"), !baseHasScheme, !systemID.hasPrefix("/"), merged.hasPrefix("/") {
                return String(merged.dropFirst())
            }
            return merged
        }
    }
}
