public extension PureXML.Model {
    /// An optionally namespace-prefixed XML name such as `xs:element`.
    struct QualifiedName: Equatable, Hashable, Sendable, CustomStringConvertible {
        /// Namespace prefix preceding the colon, when present (`xs` in `xs:element`).
        public var prefix: String?

        /// The local part of the name (`element` in `xs:element`).
        public var localName: String

        public init(prefix: String? = nil, localName: String) {
            self.prefix = prefix
            self.localName = localName
        }

        /// Parses a raw `prefix:local` or bare `local` name.
        public init(_ raw: String) {
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

        /// The full `prefix:local` rendering used in serialized output.
        public var description: String {
            guard let prefix else { return localName }
            return "\(prefix):\(localName)"
        }
    }
}
