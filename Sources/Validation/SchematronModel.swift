extension PureXML.Validation {
    /// One `<assert>` or `<report>`: a compiled XPath test and its message. An
    /// assert flags when its test is false; a report flags when its test is true.
    struct SchematronAssertion {
        let isReport: Bool
        let test: PureXML.XPath.Query
        let message: String
    }

    /// One `<rule>`: a compiled context that selects the nodes the rule fires on,
    /// and its assertions.
    struct SchematronRule {
        let context: PureXML.XPath.Query
        let assertions: [SchematronAssertion]
    }

    /// One `<pattern>`: a list of rules. A node is processed by the first rule in
    /// the pattern whose context selects it (the ISO Schematron firing rule).
    struct SchematronPattern {
        let rules: [SchematronRule]
    }
}
