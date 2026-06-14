extension PureXML.Schema.XSDParser {
    /// Value-space validity of the `final` and `block` derivation-control
    /// attributes (XSD 1.0 Structures). Each is `#all` or a whitespace-separated
    /// list of method tokens, but the admitted tokens depend on the component:
    ///
    /// - element `final`: `extension`, `restriction`
    /// - element `block`: `extension`, `restriction`, `substitution`
    /// - complexType `final`/`block`: `extension`, `restriction`
    /// - simpleType `final`: `list`, `union`, `restriction`
    ///
    /// `methodSet` parses these leniently (ignoring unknown tokens and admitting
    /// `substitution` everywhere), so `final="substitution"` on an element, a
    /// misspelled or miscased token (`foo`, `#All`, `Extension`), or `#all` mixed
    /// with other tokens was accepted (the elemF / st_final families). The token
    /// list is now checked against the component's exact set.
    static func derivationControlErrors(_ node: XSDTree, local: String) -> [String] {
        var errors: [String] = []
        for attribute in ["final", "block"] {
            guard let allowed = derivationControlTokens["\(local)|\(attribute)"],
                  let raw = node.attributes.first(where: { $0.name.prefix == nil && $0.name.localName == attribute })?.value
            else { continue }
            if let reason = derivationListError(raw, allowed: allowed) {
                errors.append("the '\(attribute)' value '\(raw)' on '\(local)' is not valid: \(reason)")
            }
        }
        return errors
    }

    /// The exact method tokens each component admits in `final`/`block`.
    private static let derivationControlTokens: [String: Set<String>] = [
        "element|final": ["extension", "restriction"],
        "element|block": ["extension", "restriction", "substitution"],
        "complexType|final": ["extension", "restriction"],
        "complexType|block": ["extension", "restriction"],
        "simpleType|final": ["list", "union", "restriction"],
    ]

    /// The reason a `final`/`block` value is invalid, or nil. `#all` stands alone;
    /// otherwise every whitespace-separated token must be in `allowed` (exact case),
    /// and `#all` may not be mixed with other tokens. An empty value is valid (no
    /// control).
    private static func derivationListError(_ raw: String, allowed: Set<String>) -> String? {
        let tokens = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        if tokens == ["#all"] { return nil }
        for token in tokens {
            if token == "#all" { return "'#all' may not be combined with other tokens" }
            if !allowed.contains(token) { return "'\(token)' is not one of \(allowed.sorted().joined(separator: ", "))" }
        }
        return nil
    }
}
