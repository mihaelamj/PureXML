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
    }
}
