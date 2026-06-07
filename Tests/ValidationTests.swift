@testable import PureXML
import Testing

@Suite("Validation")
struct ValidationTests {
    @Test("Duplicate attribute is an error")
    func test_duplicateAttributeIsError() {
        let element = PureXML.Model.Element(
            "input",
            attributes: [.init("id", "a"), .init("id", "b")],
        )
        let issues = PureXML.Validation.Validator().collect(.element(element))
        #expect(issues.count == 1)
        #expect(issues.first?.severity == .error)
    }

    @Test("Unique attributes validate cleanly")
    func test_uniqueAttributesValidate() throws {
        let element = PureXML.Model.Element(
            "input",
            attributes: [.init("id", "a"), .init("name", "b")],
        )
        let issues = try PureXML.validate(.element(element))
        #expect(issues.isEmpty)
    }
}
