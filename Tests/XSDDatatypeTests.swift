@testable import PureXML
import Testing

@Suite("XSD datatypes")
struct XSDDatatypeTests {
    private typealias Schema = PureXML.Schema

    private func valid(_ value: String, _ type: Schema.BuiltinType) -> Bool {
        Schema.isValid(value, type: type)
    }

    // MARK: Primitives

    @Test("boolean accepts the four lexical forms")
    func test_boolean() {
        #expect(valid("true", .boolean) && valid("false", .boolean))
        #expect(valid("0", .boolean) && valid("1", .boolean))
        #expect(!valid("True", .boolean) && !valid("yes", .boolean))
    }

    @Test("decimal and integer lexical spaces")
    func test_decimalInteger() {
        #expect(valid("-12.345", .decimal) && valid("+.5", .decimal) && valid("100", .decimal))
        #expect(!valid("1.2.3", .decimal) && !valid("1e3", .decimal))
        #expect(valid("-42", .integer) && !valid("4.0", .integer))
    }

    @Test("double accepts exponents and the special values")
    func test_double() {
        #expect(valid("1.5e-9", .double) && valid("INF", .double) && valid("-INF", .double) && valid("NaN", .double))
        #expect(!valid("1.5e", .double) && !valid("inf", .double))
    }

    @Test("bounded integer types enforce their ranges")
    func test_integerBounds() {
        #expect(valid("127", .byte) && !valid("128", .byte))
        #expect(valid("-128", .byte) && !valid("-129", .byte))
        #expect(valid("255", .unsignedByte) && !valid("-1", .unsignedByte))
        #expect(valid("1", .positiveInteger) && !valid("0", .positiveInteger))
        #expect(valid("0", .nonNegativeInteger) && !valid("-1", .nonNegativeInteger))
    }

    // MARK: Dates

    @Test("date validates field ranges and leap years")
    func test_date() {
        #expect(valid("2024-02-29", .date) && !valid("2023-02-29", .date))
        #expect(!valid("2024-02-30", .date) && !valid("2024-13-01", .date))
        #expect(valid("-0044-03-15", .date))
    }

    @Test("dateTime accepts 24:00:00 but not 24:00:01, and timezones")
    func test_dateTime() {
        #expect(valid("2026-06-08T24:00:00", .dateTime))
        #expect(!valid("2026-06-08T24:00:01", .dateTime))
        #expect(valid("2026-06-08T12:30:00Z", .dateTime) && valid("2026-06-08T12:30:00+05:30", .dateTime))
        #expect(!valid("2026-06-08T12:30:00+15:00", .dateTime))
    }

    @Test("the g* date types parse their reduced forms")
    func test_gTypes() {
        #expect(valid("--02-29", .gMonthDay) && !valid("--02-30", .gMonthDay))
        #expect(valid("---31", .gDay) && valid("--12", .gMonth) && valid("2026", .gYear))
    }

    // MARK: Other primitives

    @Test("hexBinary, base64Binary, and names")
    func test_binaryAndNames() {
        #expect(valid("0fB7", .hexBinary) && !valid("0fB", .hexBinary))
        #expect(valid("YW55", .base64Binary) && valid("YW4=", .base64Binary))
        #expect(valid("ns:local", .qName) && !valid("ns:1bad", .qName))
        #expect(valid("Hello", .ncName) && !valid("a:b", .ncName))
        #expect(valid("en-US", .language) && !valid("english-", .language))
        #expect(valid("P1Y2M3DT4H", .duration) && !valid("P", .duration) && !valid("PT", .duration))
    }

    // MARK: Facets

    @Test("whiteSpace collapse is applied before validation")
    func test_whiteSpace() {
        #expect(Schema.SimpleType(base: .token).isValid("  a   b  "))
        #expect(Schema.SimpleType(base: .int).isValid("  42  "))
    }

    @Test("length, minLength, and maxLength count characters")
    func test_lengthFacets() {
        let type = Schema.SimpleType(base: .string, facets: .init(minLength: 2, maxLength: 4))
        #expect(type.isValid("abc") && !type.isValid("a") && !type.isValid("abcde"))
    }

    @Test("pattern facets use the regex engine")
    func test_patternFacet() {
        let type = Schema.SimpleType(base: .string, facets: .init(patterns: ["[A-Z]{3}-\\d{2}"]))
        #expect(type.isValid("XYZ-42") && !type.isValid("xyz-42"))
    }

    @Test("enumeration compares in value space")
    func test_enumerationFacet() {
        let type = Schema.SimpleType(base: .decimal, facets: .init(enumeration: ["1.0", "2.5"]))
        #expect(type.isValid("1.00") && type.isValid("2.5") && !type.isValid("3"))
    }

    @Test("inclusive and exclusive ranges")
    func test_rangeFacets() {
        let inclusive = Schema.SimpleType(base: .integer, facets: .init(minInclusive: "1", maxInclusive: "10"))
        #expect(inclusive.isValid("1") && inclusive.isValid("10") && !inclusive.isValid("11"))
        let exclusive = Schema.SimpleType(base: .integer, facets: .init(minExclusive: "1", maxExclusive: "10"))
        #expect(!exclusive.isValid("1") && exclusive.isValid("2") && !exclusive.isValid("10"))
    }

    @Test("totalDigits and fractionDigits")
    func test_digitFacets() {
        let type = Schema.SimpleType(base: .decimal, facets: .init(totalDigits: 4, fractionDigits: 2))
        #expect(type.isValid("12.34") && type.isValid("12") && !type.isValid("123.45") && !type.isValid("1.234"))
    }

    @Test("exact decimal comparison avoids floating-point error")
    func test_exactDecimal() {
        // 0.1 + 0.2 != 0.3 in binary; exact comparison handles boundary values.
        let type = Schema.SimpleType(base: .decimal, facets: .init(maxInclusive: "0.3"))
        #expect(type.isValid("0.3") && type.isValid("0.30") && !type.isValid("0.30000000001"))
    }
}
