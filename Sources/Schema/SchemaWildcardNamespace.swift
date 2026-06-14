extension PureXML.Schema.XSDParser {
    /// Validity of an `any`/`anyAttribute` `namespace` constraint (XSD 1.0 Structures):
    ///
    ///     namespace ::= ('##any' | '##other')
    ///                 | List of (anyURI | '##targetNamespace' | '##local')
    ///
    /// So `##any` and `##other` stand alone, and a list admits only namespace URIs
    /// and the `##targetNamespace`/`##local` tokens. A misspelled token (`##all`,
    /// `##target`) or `##any`/`##other` placed inside a list (`##any ##other`) was
    /// accepted, because the wildcard parser mapped any unrecognised token to a
    /// literal URI; it is now rejected at compile time.
    static func wildcardNamespaceErrors(_ node: XSDTree) -> [String] {
        // The wildcard's own constraint is the unprefixed `namespace`; a prefixed
        // (foreign) attribute that merely shares the local name is the author's own
        // and is not checked, as `attributeApplicabilityErrors` also requires.
        guard let raw = node.attributes.first(where: { $0.name.prefix == nil && $0.name.localName == "namespace" })?.value
        else { return [] }
        return validWildcardNamespace(raw)
            ? []
            : ["the wildcard namespace '\(raw)' is not a valid namespace constraint"]
    }

    private static func validWildcardNamespace(_ raw: String) -> Bool {
        let tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        // `##any`/`##other` are valid only as the whole value, never as a list item.
        if tokens == ["##any"] || tokens == ["##other"] { return true }
        return tokens.allSatisfy { token in
            switch token {
            case "##targetNamespace", "##local": true
            case "##any", "##other": false
            default: !token.hasPrefix("##")
            }
        }
    }
}
