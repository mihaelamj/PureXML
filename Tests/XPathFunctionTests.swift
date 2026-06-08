@testable import PureXML
import Testing

@Suite("XPath functions")
struct XPathFunctionTests {
    private func doc() throws -> PureXML.Model.Node {
        try PureXML.parse(
            "<doc xml:lang=\"en\">"
                + "<item id=\"a\">  hello   world  </item>"
                + "<item id=\"b\">12</item>"
                + "<item id=\"c\">8</item>"
                + "<ns:tag xmlns:ns=\"urn:x\">x</ns:tag>"
                + "</doc>",
        )
    }

    private func string(_ path: String) throws -> String {
        try PureXML.XPath.Query(path).string(over: doc())
    }

    private func number(_ path: String) throws -> Double {
        try PureXML.XPath.Query(path).number(over: doc())
    }

    private func boolean(_ path: String) throws -> Bool {
        try PureXML.XPath.Query(path).boolean(over: doc())
    }

    // MARK: String functions

    @Test("concat, starts-with, contains")
    func test_stringPredicates() throws {
        #expect(try string("concat('a', 'b', 'c')") == "abc")
        #expect(try boolean("starts-with('hello', 'he')"))
        #expect(try boolean("contains('hello', 'ell')"))
        #expect(try !boolean("contains('hello', 'z')"))
    }

    @Test("substring-before and substring-after")
    func test_substringAround() throws {
        #expect(try string("substring-before('1999/04', '/')") == "1999")
        #expect(try string("substring-after('1999/04', '/')") == "04")
    }

    @Test("substring honors one-based positions and length")
    func test_substring() throws {
        #expect(try string("substring('hello', 2)") == "ello")
        #expect(try string("substring('hello', 2, 3)") == "ell")
        #expect(try string("substring('hello', 0, 3)") == "he")
    }

    @Test("string-length and normalize-space")
    func test_lengthAndNormalize() throws {
        #expect(try number("string-length('hello')") == 5)
        #expect(try string("normalize-space(//item[@id='a'])") == "hello world")
    }

    @Test("translate maps and deletes characters")
    func test_translate() throws {
        #expect(try string("translate('bar', 'abc', 'ABC')") == "BAr")
        #expect(try string("translate('--aaa--', 'abc-', 'ABC')") == "AAA")
    }

    // MARK: Number functions

    @Test("sum, floor, ceiling, round")
    func test_numberFunctions() throws {
        #expect(try number("sum(//item[@id='b' or @id='c'])") == 20)
        #expect(try number("floor(2.7)") == 2)
        #expect(try number("ceiling(2.1)") == 3)
        #expect(try number("round(2.5)") == 3)
        #expect(try number("round(-2.5)") == -2)
    }

    // MARK: Node functions

    @Test("local-name, name, namespace-uri")
    func test_nodeNaming() throws {
        #expect(try string("local-name(//ns:tag)") == "tag")
        #expect(try string("name(//ns:tag)") == "ns:tag")
        #expect(try string("namespace-uri(//ns:tag)") == "urn:x")
    }

    @Test("id selects elements by their id attribute")
    func test_id() throws {
        #expect(try PureXML.XPath.Query("id('b')").strings(over: doc()) == ["12"])
        #expect(try PureXML.XPath.Query("id('a c')").evaluate(over: doc()).count == 2)
    }

    @Test("lang tests the inherited xml:lang")
    func test_lang() throws {
        // lang() reads the context node, so it is exercised inside a predicate.
        #expect(try PureXML.XPath.Query("//item[lang('en')]").evaluate(over: doc()).count == 3)
        #expect(try PureXML.XPath.Query("//item[lang('fr')]").evaluate(over: doc()).isEmpty)
    }
}
