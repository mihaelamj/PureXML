import Testing
@testable import PureXML

@Suite("XSD whiteSpace facet valid restriction (Part 2 §4.3.6)")
struct SchemaWhiteSpaceRestrictionTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema \(xsd)>\(body)</xs:schema>")) != nil
    }

    private func chain(_ baseWS: String, _ derivedWS: String) -> String {
        "<xs:simpleType name=\"a\"><xs:restriction base=\"xs:string\">"
            + "<xs:whiteSpace value=\"\(baseWS)\"/></xs:restriction></xs:simpleType>"
            + "<xs:simpleType name=\"b\"><xs:restriction base=\"a\">"
            + "<xs:whiteSpace value=\"\(derivedWS)\"/></xs:restriction></xs:simpleType>"
    }

    @Test("Relaxing the base whiteSpace is rejected")
    func test_relaxRejected() {
        #expect(!compiles(chain("collapse", "replace")))
        #expect(!compiles(chain("collapse", "preserve")))
        #expect(!compiles(chain("replace", "preserve")))
    }

    @Test("Keeping or strengthening the base whiteSpace compiles")
    func test_strengthenAccepted() {
        #expect(compiles(chain("collapse", "collapse")))
        #expect(compiles(chain("replace", "collapse")))
        #expect(compiles(chain("preserve", "collapse")))
        #expect(compiles(chain("preserve", "replace")))
    }

    @Test("Relaxing a built-in's intrinsic whiteSpace is rejected")
    func test_builtinIntrinsicRespected() {
        // xs:token has intrinsic whiteSpace=collapse; a restriction may not relax it.
        #expect(!compiles(
            "<xs:simpleType name=\"t\"><xs:restriction base=\"xs:token\">"
                + "<xs:whiteSpace value=\"replace\"/></xs:restriction></xs:simpleType>",
        ))
        // Restating collapse on a token is fine.
        #expect(compiles(
            "<xs:simpleType name=\"t\"><xs:restriction base=\"xs:token\">"
                + "<xs:whiteSpace value=\"collapse\"/></xs:restriction></xs:simpleType>",
        ))
        // Strengthening xs:string (preserve) to collapse is fine.
        #expect(compiles(
            "<xs:simpleType name=\"t\"><xs:restriction base=\"xs:string\">"
                + "<xs:whiteSpace value=\"collapse\"/></xs:restriction></xs:simpleType>",
        ))
    }
}
