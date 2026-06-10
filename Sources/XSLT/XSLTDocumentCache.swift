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
