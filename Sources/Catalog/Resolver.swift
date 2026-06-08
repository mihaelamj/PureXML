extension PureXML.Catalog {
    /// A longest-prefix rewrite rule (`rewriteSystem`, `rewriteURI`).
    struct RewriteRule: Sendable {
        let startString: String
        let rewritePrefix: String
    }

    /// A longest-prefix delegation rule (`delegateSystem`, `delegatePublic`,
    /// `delegateURI`): a matching identifier is resolved by the catalog at
    /// `catalog` instead.
    struct DelegateRule: Sendable {
        let startString: String
        let catalog: String
    }

    /// A longest-suffix rewrite rule (`systemSuffix`, `uriSuffix`): an identifier
    /// ending in `suffixString` maps to `uri`.
    struct SuffixRule: Sendable {
        let suffixString: String
        let uri: String
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
        private let delegateSystem: [DelegateRule]
        private let delegatePublic: [DelegateRule]
        private let delegateURI: [DelegateRule]
        private let systemSuffix: [SuffixRule]
        private let uriSuffix: [SuffixRule]
        private let nextCatalogs: [String]
        /// Whether `public` entries are consulted for an external identifier that
        /// also carries a system identifier (`prefer="public"`). A system match
        /// always wins; this only governs the fallback.
        private let preferPublic: Bool
        /// Per-`public`-entry preference, set when a `group`/`catalog` `prefer`
        /// overrides the catalog default for that entry. A public id absent here
        /// falls back to ``preferPublic``.
        private let publicPrefer: [String: Bool]

        /// Parses an OASIS XML catalog document. Replacement URIs are resolved
        /// against `baseURI` (the catalog's own location) and any in-scope
        /// `xml:base`, so a catalog that uses relative URIs resolves them like a
        /// validating processor would. An empty `baseURI` leaves relative URIs as
        /// written.
        public init(_ xml: String, baseURI: String = "") throws {
            self = try CatalogParser.parse(xml, baseURI: baseURI)
        }

        /// Parses a legacy SGML Open (OASIS TR 9401) catalog. Replacement URIs are
        /// resolved against `baseURI` and any `BASE` entry.
        public init(sgml text: String, baseURI: String = "") {
            self = SGMLCatalogParser.parse(text, baseURI: baseURI)
        }

        init(
            systemMap: [String: String],
            publicMap: [String: String],
            uriMap: [String: String],
            rewriteSystem: [RewriteRule],
            rewriteURI: [RewriteRule],
            delegateSystem: [DelegateRule] = [],
            delegatePublic: [DelegateRule] = [],
            delegateURI: [DelegateRule] = [],
            systemSuffix: [SuffixRule] = [],
            uriSuffix: [SuffixRule] = [],
            nextCatalogs: [String] = [],
            preferPublic: Bool = true,
            publicPrefer: [String: Bool] = [:],
        ) {
            self.systemMap = systemMap
            self.publicMap = publicMap
            self.uriMap = uriMap
            self.rewriteSystem = rewriteSystem
            self.rewriteURI = rewriteURI
            self.delegateSystem = delegateSystem
            self.delegatePublic = delegatePublic
            self.delegateURI = delegateURI
            self.systemSuffix = systemSuffix
            self.uriSuffix = uriSuffix
            self.nextCatalogs = nextCatalogs
            self.preferPublic = preferPublic
            self.publicPrefer = publicPrefer
        }

        /// Resolves a system identifier: an exact `system` entry, else the longest
        /// matching `rewriteSystem` prefix, else the longest matching `systemSuffix`.
        public func resolveSystem(_ systemID: String) -> String? {
            systemMap[systemID]
                ?? Self.rewrite(systemID, with: rewriteSystem)
                ?? Self.suffix(systemID, with: systemSuffix)
        }

        /// Resolves a public identifier against the `public` entries.
        public func resolvePublic(_ publicID: String) -> String? {
            publicMap[publicID]
        }

        /// Resolves a URI name: an exact `uri` entry, else the longest matching
        /// `rewriteURI` prefix, else the longest matching `uriSuffix`.
        public func resolveURI(_ name: String) -> String? {
            uriMap[name]
                ?? Self.rewrite(name, with: rewriteURI)
                ?? Self.suffix(name, with: uriSuffix)
        }

        /// Resolves an external identifier the way a parser would: a system match
        /// always wins; the public identifier is consulted as a fallback only when
        /// `prefer="public"` or no system identifier was given (the OASIS rule).
        public func resolveExternalIdentifier(publicID: String?, systemID: String?) -> String? {
            if let systemID, let resolved = resolveSystem(systemID) {
                return resolved
            }
            guard let publicID, let resolved = resolvePublic(publicID) else { return nil }
            let entryPrefer = publicPrefer[publicID] ?? preferPublic
            return entryPrefer || systemID == nil ? resolved : nil
        }

        /// Resolves a system identifier, following `delegateSystem` and
        /// `nextCatalog` chains: the local entries are tried first, then the
        /// catalog named by the longest matching delegate prefix, then each
        /// `nextCatalog` in turn. `loadingCatalog` fetches a catalog document by
        /// URI; nil refuses it, and already-visited catalogs are skipped.
        public func resolveSystem(_ systemID: String, loadingCatalog: (String) -> String?) -> String? {
            var visited: Set<String> = []
            return chained(systemID, delegates: delegateSystem, pick: { $0.resolveSystem(systemID) }, loadingCatalog, &visited)
        }

        /// Resolves a public identifier, following `delegatePublic` and
        /// `nextCatalog` chains. See ``resolveSystem(_:loadingCatalog:)``.
        public func resolvePublic(_ publicID: String, loadingCatalog: (String) -> String?) -> String? {
            var visited: Set<String> = []
            return chained(publicID, delegates: delegatePublic, pick: { $0.resolvePublic(publicID) }, loadingCatalog, &visited)
        }

        /// Resolves a URI name, following `delegateURI` and `nextCatalog` chains.
        /// See ``resolveSystem(_:loadingCatalog:)``.
        public func resolveURI(_ name: String, loadingCatalog: (String) -> String?) -> String? {
            var visited: Set<String> = []
            return chained(name, delegates: delegateURI, pick: { $0.resolveURI(name) }, loadingCatalog, &visited)
        }

        private func chained(
            _ identifier: String,
            delegates: [DelegateRule],
            pick: (Resolver) -> String?,
            _ loadingCatalog: (String) -> String?,
            _ visited: inout Set<String>,
        ) -> String? {
            if let local = pick(self) { return local }
            let matching = delegates
                .filter { identifier.hasPrefix($0.startString) }
                .sorted { $0.startString.count > $1.startString.count }
            for rule in matching {
                if let sub = load(rule.catalog, loadingCatalog, &visited), let resolved = pick(sub) { return resolved }
            }
            for next in nextCatalogs {
                guard let sub = load(next, loadingCatalog, &visited) else { continue }
                if let resolved = sub.chained(identifier, delegates: [], pick: pick, loadingCatalog, &visited) { return resolved }
            }
            return nil
        }

        private func load(_ uri: String, _ loadingCatalog: (String) -> String?, _ visited: inout Set<String>) -> Resolver? {
            guard !visited.contains(uri), let text = loadingCatalog(uri) else { return nil }
            visited.insert(uri)
            return try? Resolver(text)
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

        /// The URI of the rule whose `suffixString` is the longest suffix of
        /// `input`, or nil when none matches.
        private static func suffix(_ input: String, with rules: [SuffixRule]) -> String? {
            rules
                .filter { input.hasSuffix($0.suffixString) }
                .max { $0.suffixString.count < $1.suffixString.count }?
                .uri
        }
    }
}
