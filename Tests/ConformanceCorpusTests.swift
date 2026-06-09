@testable import PureXML
import Testing

/// A first Tier-2 conformance corpus, driven through the validation framework:
/// each case runs a PureXML subsystem and the `Conformance` validation rule
/// reports any divergence from the spec-authoritative expected output.
@Suite("Conformance corpus (validation-driven)")
struct ConformanceCorpusTests {
    private struct Spec {
        let name: String
        let input: String
        let expected: String
    }

    /// Canonical XML 1.0 (inclusive, no comments) conformance points, with the
    /// expected canonical form taken from the specification's rules.
    private func canonicalCorpus() throws -> [PureXML.Validation.ConformanceCase] {
        let specs = [
            Spec(name: "attribute-ordering", input: "<e b=\"2\" a=\"1\"></e>", expected: "<e a=\"1\" b=\"2\"></e>"),
            Spec(name: "empty-element-expanded", input: "<e/>", expected: "<e></e>"),
            Spec(name: "comments-removed", input: "<e><!--c-->x</e>", expected: "<e>x</e>"),
            Spec(name: "cdata-becomes-escaped-text", input: "<e><![CDATA[<x>&]]></e>", expected: "<e>&lt;x&gt;&amp;</e>"),
            Spec(name: "processing-instruction", input: "<e><?pi data?></e>", expected: "<e><?pi data?></e>"),
            Spec(name: "namespace-rendered", input: "<e xmlns=\"urn:x\"></e>", expected: "<e xmlns=\"urn:x\"></e>"),
        ]
        return try specs.map { spec in
            let actual = try PureXML.Canonical.canonicalize(PureXML.parse(spec.input))
            return PureXML.Validation.ConformanceCase(name: spec.name, actual: actual, expected: spec.expected)
        }
    }

    private struct XPathSpec {
        let name: String
        let expression: String
        let expected: String
    }

    /// XPath 1.0 core-function conformance points: the function's result coerced
    /// to a string, against the value the specification mandates.
    private func xpathCorpus() throws -> [PureXML.Validation.ConformanceCase] {
        let document = try PureXML.parse("<r><item/><item/><item/></r>")
        let specs = [
            XPathSpec(name: "concat", expression: "concat('a','b','c')", expected: "abc"),
            XPathSpec(name: "substring-length", expression: "substring('12345',2,3)", expected: "234"),
            XPathSpec(name: "substring-open", expression: "substring('12345',2)", expected: "2345"),
            XPathSpec(name: "string-length", expression: "string-length('hello')", expected: "5"),
            XPathSpec(name: "normalize-space", expression: "normalize-space('  a  b  ')", expected: "a b"),
            XPathSpec(name: "translate", expression: "translate('bar','abc','ABC')", expected: "BAr"),
            XPathSpec(name: "substring-before", expression: "substring-before('a/b','/')", expected: "a"),
            XPathSpec(name: "substring-after", expression: "substring-after('a/b','/')", expected: "b"),
            XPathSpec(name: "contains", expression: "contains('hello','ell')", expected: "true"),
            XPathSpec(name: "starts-with", expression: "starts-with('hello','he')", expected: "true"),
            XPathSpec(name: "round-half-up", expression: "round(2.5)", expected: "3"),
            XPathSpec(name: "floor", expression: "floor(2.9)", expected: "2"),
            XPathSpec(name: "ceiling", expression: "ceiling(2.1)", expected: "3"),
            XPathSpec(name: "count", expression: "count(//item)", expected: "3"),
            XPathSpec(name: "div-by-zero-infinity", expression: "1 div 0", expected: "Infinity"),
            XPathSpec(name: "zero-div-zero-nan", expression: "0 div 0", expected: "NaN"),
        ]
        return try specs.map { spec in
            let actual = try PureXML.XPath.Query(spec.expression).string(over: document)
            return PureXML.Validation.ConformanceCase(name: spec.name, actual: actual, expected: spec.expected)
        }
    }

    private struct DatatypeSpec {
        let name: String
        let base: String
        let facets: String
        let value: String
        let valid: Bool
    }

    /// XSD datatype and facet conformance: an instance is validated against an
    /// element whose simple type restricts `base` with `facets`, and the verdict
    /// (valid / invalid) is checked against the specification.
    private func datatypeCorpus() throws -> [PureXML.Validation.ConformanceCase] {
        let specs = [
            DatatypeSpec(name: "integer-valid", base: "xs:integer", facets: "", value: "42", valid: true),
            DatatypeSpec(name: "integer-rejects-decimal", base: "xs:integer", facets: "", value: "4.2", valid: false),
            DatatypeSpec(name: "minInclusive-ok", base: "xs:int", facets: "<xs:minInclusive value=\"0\"/>", value: "5", valid: true),
            DatatypeSpec(name: "minInclusive-fail", base: "xs:int", facets: "<xs:minInclusive value=\"0\"/>", value: "-1", valid: false),
            DatatypeSpec(name: "maxInclusive-fail", base: "xs:int", facets: "<xs:maxInclusive value=\"10\"/>", value: "11", valid: false),
            DatatypeSpec(name: "length-ok", base: "xs:string", facets: "<xs:length value=\"3\"/>", value: "abc", valid: true),
            DatatypeSpec(name: "length-fail", base: "xs:string", facets: "<xs:length value=\"3\"/>", value: "ab", valid: false),
            DatatypeSpec(name: "pattern-ok", base: "xs:string", facets: "<xs:pattern value=\"[a-z]+\"/>", value: "abc", valid: true),
            DatatypeSpec(name: "pattern-fail", base: "xs:string", facets: "<xs:pattern value=\"[a-z]+\"/>", value: "ab1", valid: false),
            DatatypeSpec(name: "enumeration-ok", base: "xs:string", facets: "<xs:enumeration value=\"red\"/><xs:enumeration value=\"green\"/>", value: "red", valid: true),
            DatatypeSpec(name: "enumeration-fail", base: "xs:string", facets: "<xs:enumeration value=\"red\"/><xs:enumeration value=\"green\"/>", value: "blue", valid: false),
            DatatypeSpec(name: "boolean-ok", base: "xs:boolean", facets: "", value: "true", valid: true),
            DatatypeSpec(name: "boolean-fail", base: "xs:boolean", facets: "", value: "yes", valid: false),
        ]
        return try specs.map { spec in
            let xsd = """
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
              <xs:element name="v"><xs:simpleType><xs:restriction base="\(spec.base)">\(spec.facets)</xs:restriction></xs:simpleType></xs:element>
            </xs:schema>
            """
            let errors = try PureXML.Schema.Document(xsd).validate("<v>\(spec.value)</v>")
            return PureXML.Validation.ConformanceCase(
                name: spec.name,
                actual: errors.isEmpty ? "valid" : "invalid",
                expected: spec.valid ? "valid" : "invalid",
            )
        }
    }

    private struct RelaxNGSpec {
        let name: String
        let schema: String
        let xml: String
        let valid: Bool
    }

    /// RELAX NG pattern conformance: an instance is validated against a compact
    /// schema, and the verdict is checked against the pattern's semantics.
    private func relaxNGCorpus() throws -> [PureXML.Validation.ConformanceCase] {
        let specs = [
            RelaxNGSpec(name: "text-ok", schema: "start = element a { text }", xml: "<a>hi</a>", valid: true),
            RelaxNGSpec(name: "text-rejects-child", schema: "start = element a { text }", xml: "<a><b/></a>", valid: false),
            RelaxNGSpec(name: "optional-present", schema: "start = element a { element b { text }? }", xml: "<a><b>x</b></a>", valid: true),
            RelaxNGSpec(name: "optional-absent", schema: "start = element a { element b { text }? }", xml: "<a></a>", valid: true),
            RelaxNGSpec(name: "oneOrMore-fail", schema: "start = element a { element b { text }+ }", xml: "<a></a>", valid: false),
            RelaxNGSpec(name: "choice-ok", schema: "start = element a { element b { text } | element c { text } }", xml: "<a><c>y</c></a>", valid: true),
            RelaxNGSpec(name: "group-order-fail", schema: "start = element a { element b { text }, element c { text } }", xml: "<a><c>y</c><b>x</b></a>", valid: false),
            RelaxNGSpec(name: "attribute-required", schema: "start = element a { attribute id { text } }", xml: "<a></a>", valid: false),
            RelaxNGSpec(name: "attribute-ok", schema: "start = element a { attribute id { text } }", xml: "<a id='1'></a>", valid: true),
            RelaxNGSpec(name: "interleave-order-independent", schema: "start = element a { element b { text } & element c { text } }", xml: "<a><c>y</c><b>x</b></a>", valid: true),
            RelaxNGSpec(name: "empty-ok", schema: "start = element a { empty }", xml: "<a></a>", valid: true),
            RelaxNGSpec(name: "empty-rejects-text", schema: "start = element a { empty }", xml: "<a>x</a>", valid: false),
        ]
        return try specs.map { spec in
            let conforms = try PureXML.Schema.RelaxNG(compact: spec.schema).validate(spec.xml)
            return PureXML.Validation.ConformanceCase(
                name: spec.name,
                actual: conforms ? "valid" : "invalid",
                expected: spec.valid ? "valid" : "invalid",
            )
        }
    }

    private struct XSLTSpec {
        let name: String
        let stylesheet: String
        let source: String
        let expected: String
    }

    /// A text-output stylesheet wrapping a single `match="/"` template body, so
    /// the result is exactly the body's output with no stray whitespace.
    private func textSheet(_ body: String) -> String {
        "<xsl:stylesheet version=\"1.0\" xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\">"
            + "<xsl:output method=\"text\"/><xsl:template match=\"/\">\(body)</xsl:template></xsl:stylesheet>"
    }

    /// XSLT 1.0 transformation conformance: a stylesheet over a source, with the
    /// text result checked against what the spec prescribes.
    private func xsltCorpus() throws -> [PureXML.Validation.ConformanceCase] {
        let multiTemplate = "<xsl:stylesheet version=\"1.0\" xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\">"
            + "<xsl:output method=\"text\"/>"
            + "<xsl:template match=\"/\"><xsl:apply-templates select=\"/r/i\"/></xsl:template>"
            + "<xsl:template match=\"i\">[<xsl:value-of select=\".\"/>]</xsl:template></xsl:stylesheet>"
        let calling = "<xsl:stylesheet version=\"1.0\" xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\">"
            + "<xsl:output method=\"text\"/>"
            + "<xsl:template match=\"/\"><xsl:call-template name=\"greet\"><xsl:with-param name=\"who\" select=\"'world'\"/></xsl:call-template></xsl:template>"
            + "<xsl:template name=\"greet\"><xsl:param name=\"who\"/>hi <xsl:value-of select=\"$who\"/></xsl:template></xsl:stylesheet>"
        let specs = [
            XSLTSpec(name: "value-of", stylesheet: textSheet("<xsl:value-of select=\"/r/x\"/>"), source: "<r><x>hi</x></r>", expected: "hi"),
            XSLTSpec(
                name: "for-each",
                stylesheet: textSheet("<xsl:for-each select=\"/r/i\"><xsl:value-of select=\".\"/></xsl:for-each>"),
                source: "<r><i>a</i><i>b</i></r>",
                expected: "ab",
            ),
            XSLTSpec(name: "if", stylesheet: textSheet("<xsl:if test=\"/r/x\">yes</xsl:if>"), source: "<r><x>1</x></r>", expected: "yes"),
            XSLTSpec(
                name: "choose-otherwise",
                stylesheet: textSheet("<xsl:choose><xsl:when test=\"1=2\">no</xsl:when><xsl:otherwise>else</xsl:otherwise></xsl:choose>"),
                source: "<x/>",
                expected: "else",
            ),
            XSLTSpec(
                name: "sort",
                stylesheet: textSheet("<xsl:for-each select=\"/r/i\"><xsl:sort select=\".\"/><xsl:value-of select=\".\"/></xsl:for-each>"),
                source: "<r><i>3</i><i>1</i><i>2</i></r>",
                expected: "123",
            ),
            XSLTSpec(name: "variable", stylesheet: textSheet("<xsl:variable name=\"v\" select=\"'x'\"/><xsl:value-of select=\"$v\"/>"), source: "<x/>", expected: "x"),
            XSLTSpec(name: "format-number", stylesheet: textSheet("<xsl:value-of select=\"format-number(1234.5,'#,##0.00')\"/>"), source: "<x/>", expected: "1,234.50"),
            XSLTSpec(name: "concat", stylesheet: textSheet("<xsl:value-of select=\"concat(/r/a,'-',/r/b)\"/>"), source: "<r><a>x</a><b>y</b></r>", expected: "x-y"),
            XSLTSpec(name: "apply-templates", stylesheet: multiTemplate, source: "<r><i>a</i><i>b</i></r>", expected: "[a][b]"),
            XSLTSpec(name: "call-template-param", stylesheet: calling, source: "<x/>", expected: "hi world"),
        ]
        return try specs.map { spec in
            try PureXML.Validation.ConformanceCase(
                name: spec.name,
                actual: PureXML.XSLT.transform(stylesheet: spec.stylesheet, source: spec.source),
                expected: spec.expected,
            )
        }
    }

    @Test("The C14N conformance corpus passes with no located failures")
    func test_corpusConforms() throws {
        let failures = try PureXML.Validation.Conformance.failures(in: canonicalCorpus())
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }

    @Test("The XPath core-function conformance corpus passes with no located failures")
    func test_xpathCorpusConforms() throws {
        let failures = try PureXML.Validation.Conformance.failures(in: xpathCorpus())
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }

    @Test("The XSD datatype/facet conformance corpus passes with no located failures")
    func test_datatypeCorpusConforms() throws {
        let failures = try PureXML.Validation.Conformance.failures(in: datatypeCorpus())
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }

    @Test("The RELAX NG pattern conformance corpus passes with no located failures")
    func test_relaxNGCorpusConforms() throws {
        let failures = try PureXML.Validation.Conformance.failures(in: relaxNGCorpus())
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }

    @Test("The XSLT transformation conformance corpus passes with no located failures")
    func test_xsltCorpusConforms() throws {
        let failures = try PureXML.Validation.Conformance.failures(in: xsltCorpus())
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }

    @Test("A divergent case is reported as a located conformance failure")
    func test_divergenceReported() {
        let bad = PureXML.Validation.ConformanceCase(name: "wrong", actual: "<a></a>", expected: "<b></b>")
        let failures = PureXML.Validation.Conformance.failures(in: [bad])
        #expect(failures.count == 1)
        #expect(failures.first?.codingPath.map(\.stringValue) == ["wrong"])
        #expect(failures.first?.reason.contains("case 'wrong'") == true)
    }
}
