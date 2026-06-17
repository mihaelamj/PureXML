@testable import PureXML
import Testing

/// The XSD 1.0 restricted-XPath subset (Part 1, 3.11.6) for an identity
/// constraint's `selector` and `field`. A `selector` is a path of abbreviated
/// steps (`.`, `.//`, name tests, the `child::` axis); a `field` may additionally
/// end in an attribute step (`@x` or `attribute::x`). Whitespace between tokens is
/// allowed, but `//` must be adjacent and a name test's `:` may not be spaced; no
/// predicates, no absolute paths, no other axes. These pin both the rejections and
/// the valid shapes the W3C suite expects accepted (idI/idJ).
@Suite("Identity-constraint XPath subset")
struct SchemaIdentityXPathTests {
    private func compile(_ selector: String, fields: [String] = ["@v"]) throws {
        let fieldElements = fields.map { #"<xs:field xpath="\#($0)"/>"# }.joined()
        _ = try PureXML.Schema.Document(#"""
        <xs:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="root" type="xs:string"/>
          <xs:element name="r">
            <xs:complexType><xs:sequence><xs:element ref="root"/></xs:sequence></xs:complexType>
            <xs:unique name="u">
              <xs:selector xpath="\#(selector)"/>
              \#(fieldElements)
            </xs:unique>
          </xs:element>
        </xs:schema>
        """#)
    }

    private func rejectsSelector(_ selector: String) -> Bool {
        do { try compile(selector)
            return false
        } catch { return true }
    }

    private func rejectsField(_ field: String) -> Bool {
        do { try compile("root", fields: [field])
            return false
        } catch { return true }
    }

    @Test("valid selector paths compile")
    func test_validSelectors() throws {
        for selector in [".", ".//a", "a/b/c", "a|b", ".//a | .//b", "*", "ns:a", "ns:*", "child::a", "child::ns:*", ". //."] {
            try compile(selector)
        }
        // A name test built from non-ASCII NCName characters (U+203F UNDERTIE) is a
        // valid name and must not be rejected by the path lexer.
        try compile("a\u{203F}b")
    }

    @Test("valid field paths compile, including attribute steps")
    func test_validFields() throws {
        for field in ["@v", "a/@v", "attribute::v", ".//a/@v", "@ns:v", "attribute::ns:v", "a | @v", "attribute :: v"] {
            try compile("root", fields: [field])
        }
    }

    @Test("malformed selector paths are rejected")
    func test_invalidSelectors() {
        for selector in ["", "|", "| a", "a|", "/", "//", "/a", ".//", ".//.//a", "a//b", "self::a", "descendant::a", "a[1]", "child::", "tid : *", "@v", "attribute::v"] {
            #expect(rejectsSelector(selector), "expected rejection: '\(selector)'")
        }
    }

    @Test("malformed field paths are rejected")
    func test_invalidFields() {
        for field in ["", "a[1]", "@ ", "@*[1]", "/@v", "self::v", "a/@v/b", "tid : *"] {
            #expect(rejectsField(field), "expected rejection: '\(field)'")
        }
    }

    /// The content model of `unique`/`key`/`keyref` is `(annotation?, selector,
    /// field+)`: a field before the selector, a second selector, or no field is
    /// invalid, while one selector followed by one or more fields (optionally after
    /// an annotation) is valid.
    private func compilesConstraint(_ body: String) -> Bool {
        let document = #"""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="r">
            <xs:complexType><xs:sequence><xs:element name="c" type="xs:string"/></xs:sequence></xs:complexType>
            <xs:unique name="u">\#(body)</xs:unique>
          </xs:element>
        </xs:schema>
        """#
        return (try? PureXML.Schema.Document(document)) != nil
    }

    @Test("an identity constraint requires one selector then one or more fields")
    func test_identityConstraintContentModel() {
        let selector = #"<xs:selector xpath="c"/>"#
        let field = #"<xs:field xpath="@v"/>"#
        let annotation = "<xs:annotation><xs:documentation>x</xs:documentation></xs:annotation>"
        // Valid shapes.
        #expect(compilesConstraint(selector + field))
        #expect(compilesConstraint(selector + field + field))
        #expect(compilesConstraint(annotation + selector + field))
        // A field before the selector (idA044 shape).
        #expect(!compilesConstraint(field + selector))
        // Two selectors (idA046 shape).
        #expect(!compilesConstraint(selector + selector + field))
        // No field, or no selector.
        #expect(!compilesConstraint(selector))
        #expect(!compilesConstraint(field))
    }
}
