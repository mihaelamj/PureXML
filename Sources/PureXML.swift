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
}
