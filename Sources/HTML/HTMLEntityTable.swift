extension PureXML.HTML.Tokenizer {
    /// The full WHATWG named character reference set (the ~2,125 semicolon-form
    /// references), assembled from the generated parts. Vendored verbatim from
    /// `html.spec.whatwg.org/entities.json`; the decoder treats the trailing
    /// semicolon as optional (lenient tag soup) and resolves the longest match.
    static let namedEntities: [String: String] = {
        var table = namedEntities1
        table.merge(namedEntities2) { current, _ in current }
        table.merge(namedEntities3) { current, _ in current }
        return table
    }()
}
