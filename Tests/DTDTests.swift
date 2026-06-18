import Testing
@testable import PureXML

@Suite("DTD and entities")
struct DTDTests {
    private let dtdAllowed = PureXML.Parsing.Limits(allowDoctype: true)

    @Test("DOCTYPE is rejected by default")
    func test_doctypeRejectedByDefault() {
        #expect(throws: PureXML.Parsing.ParseError.self) {
            try PureXML.parse("<!DOCTYPE r [<!ENTITY x \"y\">]><r>&x;</r>")
        }
    }

    @Test("An opt-in internal entity expands in text")
    func test_internalEntityInText() throws {
        let xml = "<!DOCTYPE r [<!ENTITY who \"World\">]><r>Hello &who;!</r>"
        let node = try PureXML.parse(xml, limits: dtdAllowed)
        #expect(rootText(node) == "Hello World!")
    }

    @Test("An opt-in internal entity expands in an attribute value")
    func test_internalEntityInAttribute() throws {
        let xml = "<!DOCTYPE r [<!ENTITY v \"42\">]><r a=\"&v;\"/>"
        let node = try PureXML.parse(xml, limits: dtdAllowed)
        #expect(rootElement(node)?.attributes.first?.value == "42")
    }

    @Test("Predefined entities still work with a DTD present")
    func test_predefinedWithDTD() throws {
        let node = try PureXML.parse("<!DOCTYPE r []><r>a &amp; b</r>", limits: dtdAllowed)
        #expect(rootText(node) == "a & b")
    }

    @Test("An undeclared entity is rejected")
    func test_undeclaredEntity() {
        #expect(throws: PureXML.Parsing.ParseError.self) {
            try PureXML.parse("<!DOCTYPE r []><r>&missing;</r>", limits: dtdAllowed)
        }
    }

    @Test("A recursive entity is rejected")
    func test_recursiveEntity() {
        let xml = "<!DOCTYPE r [<!ENTITY a \"&a;\">]><r>&a;</r>"
        expectError(xml, limits: dtdAllowed) { error in
            if case .recursiveEntity = error { return true }
            return false
        }
    }

    @Test("Billion-laughs amplification is rejected")
    func test_billionLaughs() {
        let xml = "<!DOCTYPE r ["
            + "<!ENTITY l0 \"AAAAAAAAAA\">"
            + "<!ENTITY l1 \"&l0;&l0;&l0;&l0;&l0;&l0;&l0;&l0;&l0;&l0;\">"
            + "<!ENTITY l2 \"&l1;&l1;&l1;&l1;&l1;&l1;&l1;&l1;&l1;&l1;\">"
            + "]><r>&l2;</r>"
        let limits = PureXML.Parsing.Limits(allowDoctype: true, maxEntityExpansion: 100)
        expectError(xml, limits: limits) { error in
            if case .amplificationLimitExceeded = error { return true }
            return false
        }
    }

    @Test("External entities are refused, not loaded (XXE stays closed)")
    func test_externalEntityRefused() {
        // The external entity is not stored, so referencing it fails as undeclared
        // rather than reading the file: external resolution never happens.
        let xml = "<!DOCTYPE r [<!ENTITY ext SYSTEM \"file:///etc/passwd\">]><r>&ext;</r>"
        expectError(xml, limits: dtdAllowed) { error in
            if case .undefinedEntity = error { return true }
            return false
        }
    }

    private func expectError(
        _ xml: String,
        limits: PureXML.Parsing.Limits,
        matching predicate: (PureXML.Parsing.ParseError) -> Bool,
    ) {
        do {
            _ = try PureXML.parse(xml, limits: limits)
            Issue.record("expected a parse error")
        } catch let error as PureXML.Parsing.ParseError {
            #expect(predicate(error))
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }

    private func rootElement(_ node: PureXML.Model.Node) -> PureXML.Model.Element? {
        guard case let .document(children) = node else { return nil }
        for child in children {
            if case let .element(element) = child { return element }
        }
        return nil
    }

    private func rootText(_ node: PureXML.Model.Node) -> String? {
        rootElement(node)?.text
    }
}
