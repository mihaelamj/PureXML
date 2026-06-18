import Foundation
import Testing
@testable import PureXML

/// Opt-in regressions drawn from XSTS clusters fixed for #146. Requires
/// `XSTS_ROOT` pointing at the 2006-11-06 suite (same as ``XSTSSuiteTests``).
@Suite("XSTS instance regressions (opt-in via XSTS_ROOT)")
struct SchemaXSTSRegressionTests {
    private var root: String? {
        ProcessInfo.processInfo.environment["XSTS_ROOT"]
    }

    @Test("attgD019: attributeGroup anyAttribute is inherited")
    func test_attgD019() throws {
        guard let root else { return }
        let base = root.appending("/msData/attributeGroup")
        let mainXSD = try String(contentsOfFile: "\(base)/attgD019.xsd", encoding: .utf8)
        let otherXSD = try String(contentsOfFile: "\(base)/attgD019a.xsd", encoding: .utf8)
        let xml = try String(contentsOfFile: "\(base)/attgD019.xml", encoding: .utf8)
        let doc = try PureXML.Schema.Document(mainXSD)
        let loader: (String) -> String? = { loc in loc.hasSuffix("attgD019a.xsd") ? otherXSD : nil }
        #expect(try doc.validate(xml, schemaLoader: loader).isEmpty)
    }

    @Test("schA1: multi-schema xsi:schemaLocation with distinct ct-A variants")
    func test_schA1() throws {
        guard let root else { return }
        let base = root.appending("/msData/schema")
        let mainXSD = try String(contentsOfFile: "\(base)/schA1_a.xsd", encoding: .utf8)
        let xml = try String(contentsOfFile: "\(base)/schA1.xml", encoding: .utf8)
        let doc = try PureXML.Schema.Document(mainXSD)
        let loader: (String) -> String? = { loc in
            if loc.hasSuffix("schA1_b.xsd") {
                return try? String(contentsOfFile: "\(base)/schA1_b.xsd", encoding: .utf8)
            }
            if loc.hasSuffix("schA1_c.xsd") {
                return try? String(contentsOfFile: "\(base)/schA1_c.xsd", encoding: .utf8)
            }
            return nil
        }
        #expect(try doc.validate(xml, schemaLoader: loader).isEmpty)
    }

    @Test("ipo2: imported address schema with default XSD namespace")
    func test_ipo2() throws {
        guard let root else { return }
        let base = root.appending("/boeingData/ipo2")
        let mainXSD = try String(contentsOfFile: "\(base)/ipo.xsd", encoding: .utf8)
        let xml = try String(contentsOfFile: "\(base)/ipo_1.xml", encoding: .utf8)
        let addXSD = try String(contentsOfFile: "\(base)/address.xsd", encoding: .utf8)
        let doc = try PureXML.Schema.Document(mainXSD, schemaLoader: { loc in loc == "address.xsd" ? addXSD : nil })
        let loader: (String) -> String? = { loc in
            loc == "address.xsd" ? addXSD : (loc.hasSuffix("ipo.xsd") ? mainXSD : nil)
        }
        #expect(try doc.validate(xml, schemaLoader: loader).isEmpty)
    }

    @Test("attgC007: redefined attributeGroup self-reference merges base attrs")
    func test_attgC007() throws {
        guard let root else { return }
        let base = root.appending("/msData/attributeGroup")
        let mainXSD = try String(contentsOfFile: "\(base)/attgC007.xsd", encoding: .utf8)
        let xml = try String(contentsOfFile: "\(base)/attgC007.xml", encoding: .utf8)
        let redXSD = try String(contentsOfFile: "\(base)/attgC007vRed.xsd", encoding: .utf8)
        let loader: (String) -> String? = { loc in loc.hasSuffix("attgC007vRed.xsd") ? redXSD : nil }
        let doc = try PureXML.Schema.Document(mainXSD, schemaLoader: loader)
        #expect(try doc.validate(xml, schemaLoader: loader).isEmpty)
    }

    @Test("idF025: redefined complexType extension keeps base particles")
    func test_idF025() throws {
        guard let root else { return }
        let base = root.appending("/msData/identityConstraint")
        let mainXSD = try String(contentsOfFile: "\(base)/idF025.xsd", encoding: .utf8)
        let xml = try String(contentsOfFile: "\(base)/idF025.xml", encoding: .utf8)
        let redXSD = try String(contentsOfFile: "\(base)/idF025.red", encoding: .utf8)
        let loader: (String) -> String? = { loc in loc.hasSuffix("idF025.red") ? redXSD : nil }
        let doc = try PureXML.Schema.Document(mainXSD, schemaLoader: loader)
        #expect(try doc.validate(xml, schemaLoader: loader).isEmpty)
    }

    @Test("identity test suite 001: key/keyref decimal value space")
    func test_identity001() throws {
        guard let root else { return }
        let base = root.appending("/sunData/combined/identity/IdentityTestSuite/001")
        let xsd = try String(contentsOfFile: "\(base)/test.xsd", encoding: .utf8)
        let xml = try String(contentsOfFile: "\(base)/test.1.v.xml", encoding: .utf8)
        #expect(try PureXML.Schema.Document(xsd).validate(xml).isEmpty)
    }

    @Test("ipo3: xsi:type resolves imported complex type")
    func test_ipo3() throws {
        guard let root else { return }
        let base = root.appending("/boeingData/ipo3")
        let mainXSD = try String(contentsOfFile: "\(base)/ipo.xsd", encoding: .utf8)
        let xml = try String(contentsOfFile: "\(base)/ipo_1.xml", encoding: .utf8)
        let addXSD = try String(contentsOfFile: "\(base)/address.xsd", encoding: .utf8)
        let itemXSD = try String(contentsOfFile: "\(base)/itematt.xsd", encoding: .utf8)
        let loader: (String) -> String? = { loc in
            if loc.hasSuffix("address.xsd") { return addXSD }
            if loc.hasSuffix("itematt.xsd") { return itemXSD }
            return nil
        }
        let doc = try PureXML.Schema.Document(mainXSD, schemaLoader: loader)
        #expect(try doc.validate(xml, schemaLoader: loader).isEmpty)
    }

    @Test("ipo4: redefine address type with xsi:type USAddress")
    func test_ipo4() throws {
        guard let root else { return }
        let base = root.appending("/boeingData/ipo4")
        let mainXSD = try String(contentsOfFile: "\(base)/ipo.xsd", encoding: .utf8)
        let xml = try String(contentsOfFile: "\(base)/ipo_1.xml", encoding: .utf8)
        let addXSD = try String(contentsOfFile: "\(base)/address.xsd", encoding: .utf8)
        let itemXSD = try String(contentsOfFile: "\(base)/itematt.xsd", encoding: .utf8)
        let loader: (String) -> String? = { loc in
            if loc.hasSuffix("address.xsd") { return addXSD }
            if loc.hasSuffix("itematt.xsd") { return itemXSD }
            return nil
        }
        let doc = try PureXML.Schema.Document(mainXSD, schemaLoader: loader)
        let errors = try doc.validate(xml, schemaLoader: loader)
        if !errors.isEmpty {
            print("ipo4 errors:", errors.map(\.description).joined(separator: " | "))
        }
        #expect(errors.isEmpty)
    }

    @Test("identity test suite 002: QName key/keyref value space")
    func test_identity002() throws {
        guard let root else { return }
        let base = root.appending("/sunData/combined/identity/IdentityTestSuite/002")
        let xsd = try String(contentsOfFile: "\(base)/test.xsd", encoding: .utf8)
        let xml = try String(contentsOfFile: "\(base)/test.2.v.xml", encoding: .utf8)
        let errors = try PureXML.Schema.Document(xsd).validate(xml)
        if !errors.isEmpty {
            print("identity002 errors:", errors.map(\.description).joined(separator: " | "))
        }
        #expect(errors.isEmpty)
    }

    @Test("identity test suite 003: decimal key/keyref with union field xpath")
    func test_identity003() throws {
        guard let root else { return }
        let base = root.appending("/sunData/combined/identity/IdentityTestSuite/003")
        let xsd = try String(contentsOfFile: "\(base)/test.xsd", encoding: .utf8)
        let xml = try String(contentsOfFile: "\(base)/test.1.v.xml", encoding: .utf8)
        #expect(try PureXML.Schema.Document(xsd).validate(xml).isEmpty)
    }

    @Test("particlesZ003: imported element ref resolves namespace prefix on node")
    func test_particlesZ003() throws {
        guard let root else { return }
        let base = root.appending("/msData/particles")
        let mainXSD = try String(contentsOfFile: "\(base)/particlesZ003.xsd", encoding: .utf8)
        let xml = try String(contentsOfFile: "\(base)/particlesZ003.xml", encoding: .utf8)
        let impXSD = try String(contentsOfFile: "\(base)/particlesZ003.imp", encoding: .utf8)
        let loader: (String) -> String? = { loc in loc.hasSuffix("particlesZ003.imp") ? impXSD : nil }
        let doc = try PureXML.Schema.Document(mainXSD, schemaLoader: loader)
        #expect(try doc.validate(xml, schemaLoader: loader).isEmpty)
    }

    @Test("ctE018: chameleon include promotes type to parent target namespace")
    func test_ctE018() throws {
        guard let root else { return }
        let base = root.appending("/msData/complexType")
        let mainXSD = try String(contentsOfFile: "\(base)/ctE018_a.xsd", encoding: .utf8)
        let xml = try String(contentsOfFile: "\(base)/ctE018.xml", encoding: .utf8)
        let incXSD = try String(contentsOfFile: "\(base)/ctE018_b.xsd", encoding: .utf8)
        let loader: (String) -> String? = { loc in loc.hasSuffix("ctE018_b.xsd") ? incXSD : nil }
        let doc = try PureXML.Schema.Document(mainXSD, schemaLoader: loader)
        #expect(try doc.validate(xml, schemaLoader: loader).isEmpty)
    }

    @Test("Arabic block pattern matches per Unicode scalar")
    func test_arabicBlockPattern() throws {
        guard let root else { return }
        let base = root.appending("/msData/regex")
        let xsd = try String(contentsOfFile: "\(base)/Arabic.xsd", encoding: .utf8)
        let xml = try String(contentsOfFile: "\(base)/Arabic.xml", encoding: .utf8)
        #expect(try PureXML.Schema.Document(xsd).validate(xml).isEmpty)
    }
}
