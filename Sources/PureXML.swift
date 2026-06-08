/// Root namespace for the PureXML package.
public enum PureXML {
    /// XML document model types.
    public enum Model {}

    /// XML parsing types.
    public enum Parsing {}

    /// XML emitting types.
    public enum Emitting {}

    /// XML typed decoding types.
    public enum Decoding {}

    /// XML typed encoding types.
    public enum Encoding {}

    /// XML validation types.
    public enum Validation {}

    /// XML stream types.
    public enum Stream {}

    /// XPath query types.
    public enum XPath {}

    /// Streaming pattern types (the libxml2 `pattern.h` XPath subset).
    public enum Pattern {}

    /// XPointer fragment-identifier types (the `element()` and `xpointer()`
    /// schemes over XPath).
    public enum XPointer {}

    /// OASIS XML Catalog types (resolving public/system identifiers to URIs).
    public enum Catalog {}

    /// XInclude processing, URI reference resolution, and `xml:base`.
    public enum XInclude {}

    /// Canonical XML (C14N) serialization types.
    public enum Canonical {}

    /// Regular-expression types (the XML Schema regex flavor).
    public enum Regex {}
}
