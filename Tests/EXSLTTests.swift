@testable import PureXML
import Testing

@Suite("EXSLT functions: common, math, sets")
struct EXSLTTests {
    private let namespaces = [
        "exsl": PureXML.XPath.EXSLT.common,
        "math": PureXML.XPath.EXSLT.math,
        "set": PureXML.XPath.EXSLT.sets,
    ]

    private func value(_ expression: String, _ xml: String) throws -> PureXML.XPath.Value {
        let document = try PureXML.parseTree(xml)
        return try PureXML.XPath.Query(expression).value(at: document, namespaces: namespaces)
    }

    @Test("math:min, max, abs, sqrt")
    func test_mathScalars() throws {
        let numbers = "<r><n>3</n><n>1</n><n>2</n></r>"
        try #expect(value("math:max(//n)", numbers).number == 3)
        try #expect(value("math:min(//n)", numbers).number == 1)
        try #expect(value("math:abs(-5)", numbers).number == 5)
        try #expect(value("math:sqrt(9)", numbers).number == 3)
        // A non-numeric node makes min/max NaN (the EXSLT rule).
        try #expect(value("math:max(//n)", "<r><n>3</n><n>x</n></r>").number.isNaN)
    }

    @Test("math:highest and math:lowest return the extreme nodes")
    func test_mathNodes() throws {
        let numbers = "<r><n id=\"a\">3</n><n id=\"b\">1</n><n id=\"c\">3</n></r>"
        // Two nodes share the maximum value 3.
        try #expect(value("math:highest(//n)", numbers).nodes?.count == 2)
        try #expect(value("math:lowest(//n)", numbers).nodes?.count == 1)
        try #expect(value("math:lowest(//n)", numbers).string == "1")
    }

    @Test("set:distinct, difference, intersection, has-same-node")
    func test_sets() throws {
        let values = "<r><n>x</n><n>x</n><n>y</n></r>"
        try #expect(value("count(set:distinct(//n))", values).number == 2)
        let abc = "<r><a/><b/><c/></r>"
        try #expect(value("count(set:difference(//r/*, //b))", abc).number == 2) // a, c
        try #expect(value("count(set:intersection(//r/*, //b))", abc).number == 1) // b
        try #expect(value("set:has-same-node(//a, //r/*)", abc).boolean == true)
        try #expect(value("set:has-same-node(//a, //b)", abc).boolean == false)
    }

    @Test("set:leading and set:trailing relative to the first node of the second set")
    func test_setsRelative() throws {
        let abc = "<r><a/><b/><c/></r>"
        // Of a, b, c, those before b are [a]; those after b are [c].
        try #expect(value("count(set:leading(//r/*, //b))", abc).number == 1)
        try #expect(value("count(set:trailing(//r/*, //b))", abc).number == 1)
        try #expect(value("local-name(set:trailing(//r/*, //b))", abc).string == "c")
    }

    @Test("exsl:object-type reports the value type")
    func test_objectType() throws {
        let doc = "<r/>"
        try #expect(value("exsl:object-type(/r)", doc).string == "node-set")
        try #expect(value("exsl:object-type(1)", doc).string == "number")
        try #expect(value("exsl:object-type('s')", doc).string == "string")
        try #expect(value("exsl:object-type(true())", doc).string == "boolean")
    }

    @Test("An EXSLT function under an unbound prefix is an unknown function")
    func test_unboundPrefix() throws {
        #expect(throws: (any Error).self) {
            _ = try PureXML.XPath.Query("math:max(//n)").value(at: PureXML.parseTree("<r><n>1</n></r>"))
        }
    }
}
