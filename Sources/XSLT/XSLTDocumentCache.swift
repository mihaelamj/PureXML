extension PureXML.XSLT {
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
