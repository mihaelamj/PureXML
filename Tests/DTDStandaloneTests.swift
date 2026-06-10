@testable import PureXML
import Testing

/// The standalone validity constraints (2.9) and the standalone entity WFC:
/// a document declaring standalone='yes' must not depend on declarations in
/// the external subset.
@Suite("Standalone validity")
struct DTDStandaloneTests {
    private let externalDTD = """
    <!ELEMENT root (child)*>
    <!ELEMENT child (#PCDATA)>
    <!ATTLIST root token (a|b|c) "a" id ID #IMPLIED>
    <!ENTITY outside "external text">
    """

    private func resolver() -> PureXML.Parsing.EntityResolver {
        let dtd = externalDTD
        return PureXML.Parsing.EntityResolver(
            resolveEntity: { _, _ in nil },
            resolveExternalSubset: { _ in dtd },
        )
    }

    private func errors(_ xml: String) throws -> [String] {
        try PureXML.validateAgainstInternalDTD(xml, resolver: resolver()).map(\.reason)
    }

    @Test("An externally-declared default firing is a standalone violation")
    func test_externalDefault() throws {
        let xml = "<?xml version='1.0' standalone='yes'?>\n<!DOCTYPE root SYSTEM \"x.dtd\">\n<root/>"
        #expect(try errors(xml).contains { $0.contains("externally-declared default") })
        // standalone='no' is fine.
        let declared = "<?xml version='1.0' standalone='no'?>\n<!DOCTYPE root SYSTEM \"x.dtd\">\n<root/>"
        #expect(try !errors(declared).contains { $0.contains("externally-declared") })
    }

    @Test("External normalization needed is a standalone violation, supplied values are fine")
    func test_externalNormalization() throws {
        let needs = "<?xml version='1.0' standalone='yes'?>\n<!DOCTYPE root SYSTEM \"x.dtd\">\n<root token=\" b \" id=\"ok\"/>"
        #expect(try errors(needs).contains { $0.contains("externally-declared normalization") })
        let clean = "<?xml version='1.0' standalone='yes'?>\n<!DOCTYPE root SYSTEM \"x.dtd\">\n<root token=\"b\" id=\"ok\"/>"
        #expect(try !errors(clean).contains { $0.contains("normalization") })
    }

    @Test("Whitespace in externally-declared element content is a standalone violation")
    func test_externalElementWhitespace() throws {
        let xml = "<?xml version='1.0' standalone='yes'?>\n<!DOCTYPE root SYSTEM \"x.dtd\">\n<root token=\"b\" id=\"ok\">\n  <child>x</child>\n</root>"
        #expect(try errors(xml).contains { $0.contains("whitespace in the externally-declared element content") })
    }

    @Test("Internally-declared attributes do not trip the standalone rules")
    func test_internalDeclarationsExempt() throws {
        let xml = """
        <?xml version='1.0' standalone='yes'?>
        <!DOCTYPE root SYSTEM "x.dtd" [
        <!ATTLIST root token (a|b|c) "a">
        ]>
        <root token=" b " id="ok"/>
        """
        // token is internally redeclared (first wins), so its default and
        // normalization are internal facts; only external facts may fire.
        #expect(try !errors(xml).contains { $0.contains("'token'") })
    }

    @Test("A standalone document may not reference an externally-declared entity")
    func test_standaloneEntityWFC() {
        let xml = "<?xml version='1.0' standalone='yes'?>\n<!DOCTYPE root SYSTEM \"x.dtd\">\n<root token=\"b\" id=\"ok\"><child>&outside;</child></root>"
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse(xml, limits: .init(allowDoctype: true), resolver: resolver())
        }
        // Without standalone the reference resolves.
        let loose = "<!DOCTYPE root SYSTEM \"x.dtd\">\n<root token=\"b\" id=\"ok\"><child>&outside;</child></root>"
        #expect((try? PureXML.parse(loose, limits: .init(allowDoctype: true), resolver: resolver())) != nil)
    }
}
