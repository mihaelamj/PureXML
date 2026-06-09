extension PureXML.Validation {
    /// One piece of an assertion message: literal text, a `<value-of select=>`
    /// whose XPath is evaluated against the context node, or a `<name>` rendering
    /// the context node's name. Lets a finding report actual values.
    enum SchematronMessagePart {
        case text(String)
        case valueOf(PureXML.XPath.Query)
        case name
    }

    /// One `<assert>` or `<report>`: a compiled XPath test and its message
    /// template. An assert flags when its test is false; a report flags when its
    /// test is true.
    struct SchematronAssertion {
        let isReport: Bool
        let test: PureXML.XPath.Query
        let message: [SchematronMessagePart]
        /// The ids of `<diagnostic>`s referenced by the `diagnostics=` attribute,
        /// appended to a failure's message for extra detail.
        let diagnostics: [String]
    }

    /// A `<let name= value=>` variable binding: its name and the compiled XPath
    /// whose value is bound to `$name` for the rule's assertions.
    struct SchematronLet {
        let name: String
        let value: PureXML.XPath.Query
    }

    /// An `xsl:key` declaration (the XSLT query binding): its name, the compiled
    /// match selecting indexed nodes, and the `use` expression giving each node's
    /// key value, so the `key()` function can look nodes up by value.
    struct SchematronKey {
        let name: String
        let match: PureXML.XPath.Query
        let use: PureXML.XPath.Query
    }

    /// One `<rule>`: a compiled context that selects the nodes the rule fires on,
    /// its `<let>` variable bindings, and its assertions.
    struct SchematronRule {
        let context: PureXML.XPath.Query
        let lets: [SchematronLet]
        let assertions: [SchematronAssertion]
    }

    /// One `<pattern>`: an optional id (referenced by `<active>` in a phase) and a
    /// list of rules. A node is processed by the first rule in the pattern whose
    /// context selects it (the ISO Schematron firing rule).
    struct SchematronPattern {
        let id: String?
        let lets: [SchematronLet]
        let rules: [SchematronRule]
    }

    /// A compiled Schematron schema: its patterns and its phases (each phase id
    /// mapped to the pattern ids it activates), plus the declared default phase.
    struct SchematronSchema {
        let patterns: [SchematronPattern]
        let phases: [String: [String]]
        let defaultPhase: String?
        /// Schema-level `<let>` bindings, evaluated once at the document root and
        /// available to every rule's tests.
        let lets: [SchematronLet]
        /// `<diagnostic id=>` message templates, keyed by id, referenced from an
        /// assertion's `diagnostics=` attribute.
        let diagnostics: [String: [SchematronMessagePart]]
        /// `xsl:key` declarations backing the `key()` function in tests.
        let keys: [SchematronKey]
    }
}
