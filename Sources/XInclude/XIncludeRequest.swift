public extension PureXML.XInclude {
    /// A request to load one `xi:include` target, carrying the resolved URI and the
    /// include's content-negotiation hints, so a loader can honor them. PureXML
    /// performs no I/O itself; the loader decides what (if anything) to fetch.
    struct XIncludeRequest: Equatable, Sendable {
        /// The resolved absolute (or base-relative) URI to load.
        public let uri: String
        /// The `accept` attribute, an HTTP Accept hint, or nil.
        public let accept: String?
        /// The `accept-language` attribute, an HTTP Accept-Language hint, or nil.
        public let acceptLanguage: String?
        /// The `encoding` attribute for a `parse="text"` inclusion, so the loader
        /// can decode the bytes; nil for a parsed (XML) inclusion.
        public let encoding: String?
        /// Whether the inclusion is unparsed text (`parse="text"`) rather than XML.
        public let isText: Bool

        public init(
            uri: String,
            accept: String? = nil,
            acceptLanguage: String? = nil,
            encoding: String? = nil,
            isText: Bool = false,
        ) {
            self.uri = uri
            self.accept = accept
            self.acceptLanguage = acceptLanguage
            self.encoding = encoding
            self.isText = isText
        }
    }
}
