@testable import PureXML
import Testing

@Suite("XPath expressions")
struct XPathExpressionTests {
    private func shop() throws -> PureXML.Model.Node {
        try PureXML.parse(
            "<shop>"
                + "<book id=\"b1\"><title>A</title><price>10</price></book>"
                + "<book id=\"b2\"><title>B</title><price>30</price></book>"
                + "<book id=\"b3\"><title>C</title><price>50</price></book>"
                + "</shop>",
        )
    }

    private func number(_ path: String) throws -> Double {
        try PureXML.XPath.Query(path).number(over: shop())
    }

    private func string(_ path: String) throws -> String {
        try PureXML.XPath.Query(path).string(over: shop())
    }

    private func boolean(_ path: String) throws -> Bool {
        try PureXML.XPath.Query(path).boolean(over: shop())
    }

    // MARK: Arithmetic and precedence

    @Test("Arithmetic honors precedence")
    func test_arithmetic() throws {
        #expect(try number("2 + 3 * 4") == 14)
        #expect(try number("(2 + 3) * 4") == 20)
        #expect(try number("7 mod 3") == 1)
        #expect(try number("10 div 4") == 2.5)
        #expect(try number("-5 + 2") == -3)
    }

    // MARK: The four types and coercion

    @Test("Numbers render in the XPath canonical form")
    func test_numberFormatting() throws {
        #expect(try string("3") == "3")
        #expect(try string("1 div 2") == "0.5")
        #expect(try string("1 div 0") == "Infinity")
        #expect(try string("0 div 0") == "NaN")
    }

    @Test("Booleans coerce to strings and numbers")
    func test_booleanCoercion() throws {
        #expect(try string("1 = 1") == "true")
        #expect(try string("1 = 2") == "false")
        #expect(try number("true()") == 1)
    }

    @Test("count and node-set string-value")
    func test_nodeSetFunctions() throws {
        #expect(try number("count(//book)") == 3)
        #expect(try string("//title") == "A")
    }

    // MARK: Comparison

    @Test("Relational comparison over node-sets is existential")
    func test_relational() throws {
        #expect(try boolean("//price > 40"))
        #expect(try boolean("//price < 20"))
        #expect(try !boolean("//price > 100"))
    }

    @Test("Equality against a node-set matches any member")
    func test_nodeSetEquality() throws {
        #expect(try boolean("//book/@id = 'b2'"))
        #expect(try !boolean("//book/@id = 'zz'"))
    }

    @Test("Boolean operators and not()")
    func test_booleanLogic() throws {
        #expect(try boolean("1 = 1 and 2 = 2"))
        #expect(try !boolean("1 = 1 and 2 = 3"))
        #expect(try boolean("1 = 2 or 3 = 3"))
        #expect(try boolean("not(1 = 2)"))
    }

    // MARK: Predicates as expressions

    @Test("Numeric and function predicates select positionally")
    func test_predicates() throws {
        #expect(try PureXML.XPath.Query("//book[position()=2]/@id").strings(over: shop()) == ["b2"])
        #expect(try PureXML.XPath.Query("//book[last()]/@id").strings(over: shop()) == ["b3"])
        #expect(try PureXML.XPath.Query("//book[price>20]/@id").strings(over: shop()) == ["b2", "b3"])
    }

    // MARK: Union

    @Test("Union merges node-sets in document order without duplicates")
    func test_union() throws {
        let titles = try PureXML.XPath.Query("//title | //price").evaluate(over: shop())
        #expect(titles.count == 6)
    }

    // MARK: Variables

    @Test("Variable references resolve from the binding map")
    func test_variables() throws {
        let query = try PureXML.XPath.Query("$base + count(//book)")
        let value = try query.number(over: shop(), variables: ["base": .number(10)])
        #expect(value == 13)
    }

    @Test("An unbound variable is an error")
    func test_unboundVariable() throws {
        let query = try PureXML.XPath.Query("$missing")
        #expect(throws: PureXML.XPath.QueryError.self) {
            _ = try query.value(over: shop())
        }
    }

    @Test("An unknown function is an error")
    func test_unknownFunction() throws {
        let query = try PureXML.XPath.Query("bogus()")
        #expect(throws: PureXML.XPath.QueryError.self) {
            _ = try query.value(over: shop())
        }
    }
}
