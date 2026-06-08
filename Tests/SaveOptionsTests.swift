@testable import PureXML
import Testing

@Suite("Save options")
struct SaveOptionsTests {
    @Test("The serializer emits the XML declaration when requested")
    func test_declaration() {
        let options = PureXML.Emitting.Options(prettyPrint: false, includeXMLDeclaration: true)
        let xml = PureXML.serialize(.element(.init("r")), options: options)
        #expect(xml == "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<r/>")
    }

    @Test("No declaration is emitted by default")
    func test_noDeclarationByDefault() {
        #expect(PureXML.serialize(.element(.init("r")), options: .compact) == "<r/>")
    }

    @Test("Standalone and an omitted encoding are honored")
    func test_declarationVariants() {
        let options = PureXML.Emitting.Options(
            prettyPrint: false,
            includeXMLDeclaration: true,
            encodingName: nil,
            standalone: true,
        )
        let xml = PureXML.serialize(.element(.init("r")), options: options)
        #expect(xml == "<?xml version=\"1.0\" standalone=\"yes\"?>\n<r/>")
    }

    @Test("The writer emits the declaration via writeStartDocument")
    func test_writerDeclaration() {
        var writer = PureXML.Emitting.Writer(options: .init(prettyPrint: false, includeXMLDeclaration: true))
        writer.writeStartDocument()
        writer.writeStartElement("r")
        writer.writeEndElement()
        #expect(writer.output == "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<r/>")
    }
}
