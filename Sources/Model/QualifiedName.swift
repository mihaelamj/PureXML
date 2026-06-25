public extension PureXML.Model {
    /// An optionally namespace-prefixed XML name such as `xs:element`.
    struct QualifiedName: Equatable, Hashable, Sendable, CustomStringConvertible {
        /// Namespace prefix preceding the colon, when present (`xs` in `xs:element`).
        public var prefix: String?

        /// The local part of the name (`element` in `xs:element`).
        public var localName: String

        /// The resolved namespace URI, or nil when the name is in no namespace or
        /// has not been namespace-resolved. Populated by the parser from in-scope
        /// `xmlns` declarations; nil for names built directly.
        public var namespaceURI: String?

        public init(prefix: String? = nil, localName: String, namespaceURI: String? = nil) {
            self.prefix = prefix
            self.localName = localName
            self.namespaceURI = namespaceURI
        }

        /// Returns a copy of this name carrying the given resolved namespace URI.
        public func resolved(namespaceURI: String?) -> QualifiedName {
            QualifiedName(prefix: prefix, localName: localName, namespaceURI: namespaceURI)
        }

        /// Parses a raw `prefix:local` or bare `local` name. A malformed colon
        /// placement (`:local`, `prefix:`, `::`) does not split: the whole string
        /// is kept as an unprefixed local name rather than inventing an empty
        /// prefix or local part.
        public init(_ raw: String) {
            namespaceURI = nil
            if let colon = raw.firstIndex(of: ":") {
                let head = String(raw[raw.startIndex ..< colon])
                let tail = String(raw[raw.index(after: colon)...])
                if head.isEmpty || tail.isEmpty {
                    prefix = nil
                    localName = raw
                } else {
                    prefix = head
                    localName = tail
                }
            } else {
                prefix = nil
                localName = raw
            }
        }

        /// Builds a name whose first colon is already known by byte offset (the
        /// byte scanner found it while reading the name), so the prefix split
        /// needs no second scan. `colonOffset` is nil for the common unprefixed
        /// name. The split follows ``init(_:)`` exactly: a colon at the start or
        /// end (`:local`, `prefix:`) does not split. The name is all-ASCII, so a
        /// byte offset is a character offset.
        init(ascii raw: String, colonOffset: Int?) {
            namespaceURI = nil
            guard let colonOffset else {
                prefix = nil
                localName = raw
                return
            }
            let colon = raw.index(raw.startIndex, offsetBy: colonOffset)
            let head = String(raw[raw.startIndex ..< colon])
            let tail = String(raw[raw.index(after: colon)...])
            if head.isEmpty || tail.isEmpty {
                prefix = nil
                localName = raw
            } else {
                prefix = head
                localName = tail
            }
        }

        /// The full `prefix:local` rendering used in serialized output.
        public var description: String {
            guard let prefix else { return localName }
            return "\(prefix):\(localName)"
        }
    }
}
