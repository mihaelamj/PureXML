/// Accumulates catalog entries as the tree is walked. File-scope and private: an
/// internal detail of ``PureXML/Catalog/CatalogParser``.
private struct CatalogBuilder {
    typealias RewriteRule = PureXML.Catalog.RewriteRule
    typealias DelegateRule = PureXML.Catalog.DelegateRule

    var systemMap: [String: String] = [:]
    var publicMap: [String: String] = [:]
    var uriMap: [String: String] = [:]
    var rewriteSystem: [RewriteRule] = []
    var rewriteURI: [RewriteRule] = []
    var delegateSystem: [DelegateRule] = []
    var delegatePublic: [DelegateRule] = []
    var delegateURI: [DelegateRule] = []
    var nextCatalogs: [String] = []

    mutating func add(_ node: PureXML.Model.TreeNode) {
        switch node.name?.localName {
        case "system":
            insert(node, key: "systemId", value: "uri", into: &systemMap)
        case "public":
            insert(node, key: "publicId", value: "uri", into: &publicMap)
        case "uri":
            insert(node, key: "name", value: "uri", into: &uriMap)
        case "rewriteSystem":
            appendRewrite(node, start: "systemIdStartString", into: &rewriteSystem)
        case "rewriteURI":
            appendRewrite(node, start: "uriStartString", into: &rewriteURI)
        default:
            addDelegation(node)
        }
    }

    private mutating func addDelegation(_ node: PureXML.Model.TreeNode) {
        switch node.name?.localName {
        case "delegateSystem":
            appendDelegate(node, start: "systemIdStartString", into: &delegateSystem)
        case "delegatePublic":
            appendDelegate(node, start: "publicIdStartString", into: &delegatePublic)
        case "delegateURI":
            appendDelegate(node, start: "uriStartString", into: &delegateURI)
        case "nextCatalog":
            if let catalog = attribute(node, "catalog") { nextCatalogs.append(catalog) }
        default:
            break
        }
    }

    private func appendDelegate(
        _ node: PureXML.Model.TreeNode,
        start: String,
        into rules: inout [DelegateRule],
    ) {
        guard let startString = attribute(node, start), let catalog = attribute(node, "catalog") else { return }
        rules.append(DelegateRule(startString: startString, catalog: catalog))
    }

    private func insert(
        _ node: PureXML.Model.TreeNode,
        key: String,
        value: String,
        into map: inout [String: String],
    ) {
        guard let identifier = attribute(node, key), let uri = attribute(node, value) else { return }
        map[identifier] = uri
    }

    private func appendRewrite(
        _ node: PureXML.Model.TreeNode,
        start: String,
        into rules: inout [RewriteRule],
    ) {
        guard let startString = attribute(node, start), let rewrite = attribute(node, "rewritePrefix") else { return }
        rules.append(RewriteRule(startString: startString, rewritePrefix: rewrite))
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
            nextCatalogs: nextCatalogs,
        )
    }
}

extension PureXML.Catalog {
    /// Parses an OASIS XML catalog document into a ``Resolver``. Entries are
    /// matched by local name, so the catalog namespace is not required; `group`
    /// and `catalog` elements are recursed into.
    enum CatalogParser {
        static func parse(_ xml: String) throws -> Resolver {
            let root = try PureXML.parseTree(xml)
            var builder = CatalogBuilder()
            collect(root, into: &builder)
            return builder.resolver()
        }

        private static func collect(_ node: PureXML.Model.TreeNode, into builder: inout CatalogBuilder) {
            for child in node.children where child.kind == .element {
                builder.add(child)
                if child.name?.localName == "group" || child.name?.localName == "catalog" {
                    collect(child, into: &builder)
                }
            }
        }
    }
}
