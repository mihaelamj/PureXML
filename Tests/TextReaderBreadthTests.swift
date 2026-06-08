@testable import PureXML
import Testing

@Suite("TextReader breadth: attributes, namespaces, lang, position")
struct TextReaderBreadthTests {
    private func reader(_ xml: String) -> PureXML.Parsing.TextReader {
        PureXML.reader(xml)
    }

    @Test("Attribute navigation walks each attribute and returns to the element")
    func test_attributeNavigation() throws {
        var cursor = reader("<a x=\"1\" y=\"2\"/>")
        #expect(try cursor.read())
        #expect(cursor.nodeKind == .element)
        let toFirst = cursor.moveToFirstAttribute()
        #expect(toFirst)
        #expect(cursor.nodeKind == .attribute)
        #expect(cursor.name == "x")
        #expect(cursor.value == "1")
        let toSecond = cursor.moveToNextAttribute()
        #expect(toSecond)
        #expect(cursor.name == "y")
        #expect(cursor.value == "2")
        let pastLast = cursor.moveToNextAttribute()
        #expect(!pastLast)
        let toElement = cursor.moveToElement()
        #expect(toElement)
        #expect(cursor.nodeKind == .element)
        #expect(cursor.name == "a")
    }

    @Test("moveToAttribute selects by name")
    func test_moveToAttributeByName() throws {
        var cursor = reader("<a x=\"1\" y=\"2\"/>")
        #expect(try cursor.read())
        let found = cursor.moveToAttribute("y")
        #expect(found)
        #expect(cursor.value == "2")
        let missing = cursor.moveToAttribute("z")
        #expect(!missing)
    }

    @Test("namespaceURI, localName, and prefix are exposed on elements")
    func test_namespaceAccessors() throws {
        var cursor = reader("<x:a xmlns:x=\"urn:x\"><b/></x:a>")
        #expect(try cursor.read())
        #expect(cursor.nodeKind == .element)
        #expect(cursor.namespaceURI == "urn:x")
        #expect(cursor.localName == "a")
        #expect(cursor.prefix == "x")
        #expect(try cursor.read())
        #expect(cursor.localName == "b")
        #expect(cursor.namespaceURI == nil)
    }

    @Test("xml:lang is inherited by descendants and reset when it goes out of scope")
    func test_xmlLang() throws {
        var cursor = reader("<a xml:lang=\"en\"><b>hi</b></a><c/>")
        #expect(try cursor.read()) // <a>
        #expect(cursor.xmlLang == "en")
        #expect(try cursor.read()) // <b>
        #expect(cursor.xmlLang == "en")
        #expect(try cursor.read()) // text
        #expect(cursor.xmlLang == "en")
        #expect(try cursor.read()) // </b>
        #expect(try cursor.read()) // </a>
        #expect(cursor.xmlLang == nil)
    }

    @Test("A nested xml:lang overrides the inherited value")
    func test_xmlLangOverride() throws {
        var cursor = reader("<a xml:lang=\"en\"><b xml:lang=\"fr\"/></a>")
        #expect(try cursor.read()) // <a>
        #expect(cursor.xmlLang == "en")
        #expect(try cursor.read()) // <b>
        #expect(cursor.xmlLang == "fr")
    }

    @Test("Each node reports the line and column where it begins")
    func test_position() throws {
        var cursor = reader("<a>\n  <b/>\n</a>")
        #expect(try cursor.read()) // <a>
        #expect(cursor.lineNumber == 1)
        #expect(cursor.columnNumber == 1)
        #expect(try cursor.read()) // text "\n  "
        #expect(try cursor.read()) // <b/>
        #expect(cursor.nodeKind == .element)
        #expect(cursor.name == "b")
        #expect(cursor.lineNumber == 2)
        #expect(cursor.columnNumber == 3)
    }
}
