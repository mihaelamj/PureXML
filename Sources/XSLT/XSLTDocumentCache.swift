extension PureXML.XSLT {
    /// Wraps a transform's document loader as an entity resolver, so external
    /// DTDs and entities referenced by the stylesheet or source resolve
    /// through the same channel as document(). The loader is used from a
    /// single thread for the duration of one parse.
    static func loaderResolver(_ loader: @escaping (String) -> String?) -> PureXML.Parsing.EntityResolver {
        let box = LoaderBox(load: loader)
        return PureXML.Parsing.EntityResolver(
            resolveEntity: { _, id in box.load(id.resolvedSystemID) },
            resolveExternalSubset: { id in box.load(id.resolvedSystemID) },
        )
    }

    /// A single-threaded loader carried into the resolver's Sendable
    /// closures; XSLT transforms are confined to one thread.
    private struct LoaderBox: @unchecked Sendable {
        let load: (String) -> String?
    }

    /// The key indexes a transform has built, one per document root.
    final class KeyIndexCache {
        var indexes: [ObjectIdentifier: KeyIndex] = [:]
    }

    /// The documents a transform has loaded, keyed by URI: per the XSLT
    /// `document()` definition the same reference returns the identical
    /// document, so node identity (and `generate-id()`) is stable across
    /// calls within one transform.
    final class DocumentCache {
        var trees: [String: PureXML.Model.TreeNode] = [:]
        var sources: [String: PureXML.Model.Node] = [:]
        /// DTD-declared ID attributes per document root identity: element
        /// name to the names of its ID-typed attributes. A document with no
        /// entry has no IDs (the XPath id() definition needs the DTD).
        var idAttributes: [ObjectIdentifier: [String: Set<String>]] = [:]
        /// The id() index per document root, built on first use: ID value to
        /// its element (the first in document order wins, per ID semantics).
        var idIndexes: [ObjectIdentifier: [String: PureXML.Model.TreeNode]] = [:]
        /// The base URI of each loaded document, keyed by its root identity: the
        /// URI reference it was loaded from. A relative reference in `document()`
        /// resolves against the base URI of the node supplying the base (XSLT 1.0
        /// 12.1); a root absent here is the source document, whose base the loader
        /// already applies, so it resolves against the empty string.
        var baseURIs: [ObjectIdentifier: String] = [:]

        /// Registers the top stylesheet's parsed document under its base URI, so a
        /// `document('')` from the top stylesheet (whose empty reference resolves
        /// to that base) reaches it without the loader; `document('')` in an
        /// included file, a different base, still loads that file (XSLT 1.0 12.1).
        func registerSelfDocument(_ document: PureXML.Model.Node?, at baseURI: String) {
            guard !baseURI.isEmpty, let document else { return }
            trees[baseURI] = PureXML.Model.TreeNode(document)
            sources[baseURI] = document
        }
    }

    /// The ID-typed attributes a document type declares, element name to
    /// attribute names (XPath id() resolves through these).
    static func declaredIDAttributes(_ documentType: PureXML.Parsing.DocumentType) -> [String: Set<String>] {
        var declared: [String: Set<String>] = [:]
        for (element, body) in documentType.attributeLists {
            let names = PureXML.Validation.AttributeListParser.parse(body)
                .filter { $0.type == .id }
                .map(\.name)
            if !names.isEmpty { declared[element, default: []].formUnion(names) }
        }
        return declared
    }
}
