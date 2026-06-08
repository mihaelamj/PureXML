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
    }

    /// One `<rule>`: a compiled context that selects the nodes the rule fires on,
    /// and its assertions.
    struct SchematronRule {
        let context: PureXML.XPath.Query
        let assertions: [SchematronAssertion]
    }

    /// One `<pattern>`: an optional id (referenced by `<active>` in a phase) and a
    /// list of rules. A node is processed by the first rule in the pattern whose
    /// context selects it (the ISO Schematron firing rule).
    struct SchematronPattern {
        let id: String?
        let rules: [SchematronRule]
    }

    /// A compiled Schematron schema: its patterns and its phases (each phase id
    /// mapped to the pattern ids it activates), plus the declared default phase.
    struct SchematronSchema {
        let patterns: [SchematronPattern]
        let phases: [String: [String]]
        let defaultPhase: String?
    }
}
