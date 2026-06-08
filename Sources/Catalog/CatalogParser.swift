/// Accumulates catalog entries as the tree is walked. File-scope and private: an
/// internal detail of ``PureXML/Catalog/CatalogParser``.
private struct CatalogBuilder {
    typealias RewriteRule = PureXML.Catalog.RewriteRule
    typealias DelegateRule = PureXML.Catalog.DelegateRule
    typealias SuffixRule = PureXML.Catalog.SuffixRule

    var systemMap: [String: String] = [:]
    var publicMap: [String: String] = [:]
    var uriMap: [String: String] = [:]
    var rewriteSystem: [RewriteRule] = []
    var rewriteURI: [RewriteRule] = []
    var delegateSystem: [DelegateRule] = []
    var delegatePublic: [DelegateRule] = []
    var delegateURI: [DelegateRule] = []
    var systemSuffix: [SuffixRule] = []
    var uriSuffix: [SuffixRule] = []
    var nextCatalogs: [String] = []
    var preferPublic = true
    /// Each `public` entry's effective `prefer`, taken from its nearest enclosing
    /// `group`/`catalog`. Absent means the catalog-wide `preferPublic` applies.
    var publicPrefer: [String: Bool] = [:]

    mutating func add(_ node: PureXML.Model.TreeNode, base: String, prefer: Bool) {
        switch node.name?.localName {
        case "system":
            insert(node, key: "systemId", base: base, into: &systemMap)
        case "public":
            insert(node, key: "publicId", base: base, into: &publicMap)
            if let id = attribute(node, "publicId") { publicPrefer[id] = prefer }
        case "uri":
            insert(node, key: "name", base: base, into: &uriMap)
        case "rewriteSystem":
            appendRewrite(node, start: "systemIdStartString", base: base, into: &rewriteSystem)
        case "rewriteURI":
            appendRewrite(node, start: "uriStartString", base: base, into: &rewriteURI)
        case "systemSuffix":
            appendSuffix(node, suffix: "systemIdSuffix", base: base, into: &systemSuffix)
        case "uriSuffix":
            appendSuffix(node, suffix: "uriSuffix", base: base, into: &uriSuffix)
        default:
            addDelegation(node, base: base)
        }
    }

    private func appendSuffix(
        _ node: PureXML.Model.TreeNode,
        suffix: String,
        base: String,
        into rules: inout [SuffixRule],
    ) {
        guard let suffixString = attribute(node, suffix), let uri = attribute(node, "uri") else { return }
        rules.append(SuffixRule(suffixString: suffixString, uri: resolve(uri, base)))
    }

    private mutating func addDelegation(_ node: PureXML.Model.TreeNode, base: String) {
        switch node.name?.localName {
        case "delegateSystem":
            appendDelegate(node, start: "systemIdStartString", base: base, into: &delegateSystem)
        case "delegatePublic":
            appendDelegate(node, start: "publicIdStartString", base: base, into: &delegatePublic)
        case "delegateURI":
            appendDelegate(node, start: "uriStartString", base: base, into: &delegateURI)
        case "nextCatalog":
            if let catalog = attribute(node, "catalog") { nextCatalogs.append(resolve(catalog, base)) }
        default:
            break
        }
    }

    private func appendDelegate(
        _ node: PureXML.Model.TreeNode,
        start: String,
        base: String,
        into rules: inout [DelegateRule],
    ) {
        guard let startString = attribute(node, start), let catalog = attribute(node, "catalog") else { return }
        rules.append(DelegateRule(startString: startString, catalog: resolve(catalog, base)))
    }

    private func insert(
        _ node: PureXML.Model.TreeNode,
        key: String,
        base: String,
        into map: inout [String: String],
    ) {
        guard let identifier = attribute(node, key), let uri = attribute(node, "uri") else { return }
        map[identifier] = resolve(uri, base)
    }

    private func appendRewrite(
        _ node: PureXML.Model.TreeNode,
        start: String,
        base: String,
        into rules: inout [RewriteRule],
    ) {
        guard let startString = attribute(node, start), let rewrite = attribute(node, "rewritePrefix") else { return }
        rules.append(RewriteRule(startString: startString, rewritePrefix: resolve(rewrite, base)))
    }

    /// Resolves a catalog replacement URI against the in-scope base (RFC 3986). An
    /// empty base leaves a relative URI relative, so a catalog with no base behaves
    /// exactly as before.
    private func resolve(_ uri: String, _ base: String) -> String {
        base.isEmpty ? uri : PureXML.XInclude.URIReference.resolve(uri, against: base)
    }

    private func attribute(_ node: PureXML.Model.TreeNode, _ name: String) -> String? {
        node.attributes.first { $0.name.localName == name || $0.name.description == name }?.value
    }

    func resolver() -> PureXML.Catalog.Resolver {
        PureXML.Catalog.Resolver(
            systemMap: systemMap,
            publicMap: publicMap,
            uriMap: uriMap,
            rewriteSystem: rewriteSystem,
            rewriteURI: rewriteURI,
            delegateSystem: delegateSystem,
            delegatePublic: delegatePublic,
            delegateURI: delegateURI,
            systemSuffix: systemSuffix,
            uriSuffix: uriSuffix,
            nextCatalogs: nextCatalogs,
            preferPublic: preferPublic,
            publicPrefer: publicPrefer,
        )
    }
}

extension PureXML.Catalog {
    /// Parses an OASIS XML catalog document into a ``Resolver``. Entries are
    /// matched by local name, so the catalog namespace is not required; `group`
    /// and `catalog` elements are recursed into. Replacement URIs are resolved
    /// against `baseURI` and the in-scope `xml:base` (RFC 3986).
    enum CatalogParser {
        static func parse(_ xml: String, baseURI: String = "") throws -> Resolver {
            let root = try PureXML.parseTree(xml)
            var builder = CatalogBuilder()
            if let catalog = catalogElement(root), prefer(of: catalog) == "system" {
                builder.preferPublic = false
            }
            collect(root, base: baseURI, prefer: builder.preferPublic, into: &builder)
            return builder.resolver()
        }

        private static func catalogElement(_ node: PureXML.Model.TreeNode) -> PureXML.Model.TreeNode? {
            node.kind == .element ? node : node.children.first { $0.kind == .element }
        }

        private static func prefer(of node: PureXML.Model.TreeNode) -> String? {
            node.attributes.first { $0.name.localName == "prefer" }?.value
        }

        private static func collect(_ node: PureXML.Model.TreeNode, base: String, prefer: Bool, into builder: inout CatalogBuilder) {
            for child in node.children where child.kind == .element {
                let childBase = elementBase(child, base)
                // A group/catalog `prefer` attribute overrides the inherited
                // preference for its subtree (OASIS XML Catalogs §4).
                let childPrefer = preferOverride(child) ?? prefer
                builder.add(child, base: childBase, prefer: childPrefer)
                if child.name?.localName == "group" || child.name?.localName == "catalog" {
                    collect(child, base: childBase, prefer: childPrefer, into: &builder)
                }
            }
        }

        /// The explicit `prefer` on a `group`/`catalog`, or nil when it inherits.
        private static func preferOverride(_ node: PureXML.Model.TreeNode) -> Bool? {
            switch prefer(of: node) {
            case "public": true
            case "system": false
            default: nil
            }
        }

        /// The base URI in scope for `node`: its own `xml:base` (resolved against
        /// the inherited base), or the inherited base when it declares none.
        private static func elementBase(_ node: PureXML.Model.TreeNode, _ inherited: String) -> String {
            guard let xmlBase = node.attributes.first(where: { $0.name.localName == "base" && $0.name.prefix == "xml" })?.value else {
                return inherited
            }
            return inherited.isEmpty ? xmlBase : PureXML.XInclude.URIReference.resolve(xmlBase, against: inherited)
        }
    }
}
