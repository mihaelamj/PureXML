extension PureXML.Catalog {
    /// A longest-prefix rewrite rule (`rewriteSystem`, `rewriteURI`).
    struct RewriteRule: Sendable {
        let startString: String
        let rewritePrefix: String
    }
}

public extension PureXML.Catalog {
    /// An OASIS XML Catalog (the libxml2 `catalog.h` model): it maps public and
    /// system identifiers, and URI names, to replacement URIs.
    ///
    /// The catalog itself performs no I/O: it resolves an identifier to a URI
    /// string. To actually load the target, build a ``PureXML/Parsing/EntityResolver``
    /// with ``entityResolver(loadingURI:)`` and supply a closure that turns a
    /// resolved URI into text. With no such closure nothing is loaded, so XXE
    /// stays closed.
    ///
    /// Supported entries (matched by local name, namespace-agnostic): `public`,
    /// `system`, `uri`, `rewriteSystem`, `rewriteURI`, and `group` (recursed).
    struct Resolver: Sendable {
        private let systemMap: [String: String]
        private let publicMap: [String: String]
        private let uriMap: [String: String]
        private let rewriteSystem: [RewriteRule]
        private let rewriteURI: [RewriteRule]

        /// Parses an OASIS XML catalog document.
        public init(_ xml: String) throws {
            self = try CatalogParser.parse(xml)
        }

        init(
            systemMap: [String: String],
            publicMap: [String: String],
            uriMap: [String: String],
            rewriteSystem: [RewriteRule],
            rewriteURI: [RewriteRule],
        ) {
            self.systemMap = systemMap
            self.publicMap = publicMap
            self.uriMap = uriMap
            self.rewriteSystem = rewriteSystem
            self.rewriteURI = rewriteURI
        }

        /// Resolves a system identifier: an exact `system` entry, else the longest
        /// matching `rewriteSystem` prefix.
        public func resolveSystem(_ systemID: String) -> String? {
            systemMap[systemID] ?? Self.rewrite(systemID, with: rewriteSystem)
        }

        /// Resolves a public identifier against the `public` entries.
        public func resolvePublic(_ publicID: String) -> String? {
            publicMap[publicID]
        }

        /// Resolves a URI name: an exact `uri` entry, else the longest matching
        /// `rewriteURI` prefix.
        public func resolveURI(_ name: String) -> String? {
            uriMap[name] ?? Self.rewrite(name, with: rewriteURI)
        }

        /// Resolves an external identifier the way a parser would: the system
        /// identifier takes precedence (OASIS rule), then the public identifier.
        public func resolveExternalIdentifier(publicID: String?, systemID: String?) -> String? {
            if let systemID, let resolved = resolveSystem(systemID) {
                return resolved
            }
            if let publicID { return resolvePublic(publicID) }
            return nil
        }

        /// Builds a ``PureXML/Parsing/EntityResolver`` that resolves an external
        /// entity or subset through this catalog and then loads the resolved URI
        /// with `loadingURI`. An identifier the catalog cannot map, or a URI the
        /// loader returns nil for, is refused, so the default posture stays closed.
        public func entityResolver(
            loadingURI: @escaping @Sendable (_ uri: String) -> String?,
        ) -> PureXML.Parsing.EntityResolver {
            PureXML.Parsing.EntityResolver(
                resolveEntity: { _, identifier in
                    load(identifier, loadingURI)
                },
                resolveExternalSubset: { identifier in
                    load(identifier, loadingURI)
                },
            )
        }

        private func load(
            _ identifier: PureXML.Parsing.ExternalID,
            _ loadingURI: @Sendable (String) -> String?,
        ) -> String? {
            guard let uri = resolveExternalIdentifier(publicID: identifier.publicID, systemID: identifier.systemID) else {
                return nil
            }
            return loadingURI(uri)
        }

        /// The rewrite with the longest matching `startString`, applied as a prefix
        /// replacement.
        private static func rewrite(_ input: String, with rules: [RewriteRule]) -> String? {
            let best = rules
                .filter { input.hasPrefix($0.startString) }
                .max { $0.startString.count < $1.startString.count }
            guard let best else { return nil }
            return best.rewritePrefix + input.dropFirst(best.startString.count)
        }
    }
}
