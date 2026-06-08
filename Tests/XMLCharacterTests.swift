@testable import PureXML
import Testing

@Suite("XML characters")
struct XMLCharacterTests {
    private func scalar(_ value: UInt32) -> Unicode.Scalar {
        Unicode.Scalar(value) ?? " "
    }

    @Test("isChar follows the Char production")
    func test_isChar() {
        #expect(PureXML.Parsing.XMLCharacter.isChar(scalar(0x09))) // tab
        #expect(PureXML.Parsing.XMLCharacter.isChar(scalar(0x41))) // A
        #expect(!PureXML.Parsing.XMLCharacter.isChar(scalar(0x01))) // control
        #expect(!PureXML.Parsing.XMLCharacter.isChar(scalar(0xFFFE))) // non-character
    }

    @Test("Name start excludes name-only characters; name char includes them")
    func test_nameClasses() {
        let kind = PureXML.Parsing.XMLCharacter.self
        #expect(kind.isNameStart(scalar(0x03B1))) // Greek alpha
        #expect(!kind.isNameStart(scalar(0x30))) // digit
        #expect(!kind.isNameStart(scalar(0x0301))) // combining acute
        #expect(!kind.isNameStart(scalar(0x00AA))) // ordinal: a letter, but outside NameStartChar
        #expect(kind.isNameChar(scalar(0x30))) // digit
        #expect(kind.isNameChar(scalar(0x0301))) // combining acute
        #expect(kind.isNameChar(scalar(0xB7))) // middle dot
        #expect(!kind.isNameChar(scalar(0x20))) // space
    }

    @Test("isValidName accepts well-formed names and rejects the rest")
    func test_isValidName() {
        for name in ["foo", "foo-bar", "ns:local", "_x1", "\u{00E9}l", "\u{03B1}\u{0301}"] {
            #expect(PureXML.Parsing.XMLCharacter.isValidName(name), "\(name)")
        }
        for name in ["", "1abc", "-x", ".x", "a b", "a\u{0001}b"] {
            #expect(!PureXML.Parsing.XMLCharacter.isValidName(name), "\(name)")
        }
    }

    @Test("The parser accepts a non-ASCII element name")
    func test_unicodeElementName() throws {
        let node = try PureXML.parse("<\u{03B1}>x</\u{03B1}>")
        guard case let .document(children) = node, case let .element(element) = children.first else {
            Issue.record("expected a document with a root element")
            return
        }
        #expect(element.name.localName == "\u{03B1}")
        #expect(element.text == "x")
    }
}
