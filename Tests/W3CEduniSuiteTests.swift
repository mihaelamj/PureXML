import Foundation
@testable import PureXML
import Testing

/// Opt-in runner for the W3C XML Conformance Test Suite's eduni (Edinburgh)
/// sections: the XML 1.0 errata suites (2e, 3e, and the 5th-edition 4e), the
/// Namespaces 1.0 suite with its errata, and the misc cases. The XML 1.1 and
/// Namespaces 1.1 sections are out of scope: PureXML targets XML 1.0 Fifth
/// Edition. Cases marked EDITION without a 5 apply only to earlier editions
/// and are skipped; TYPE='error' cases are optional behavior by definition.
/// Point `XMLCONF_ROOT` at the extracted `xmlconf` directory to run (the
/// suite is never vendored). Foundation is used for file access only.
@Suite("W3C eduni conformance (opt-in via XMLCONF_ROOT)")
struct W3CEduniSuiteTests {
    private var root: String? {
        ProcessInfo.processInfo.environment["XMLCONF_ROOT"]
    }

    /// Sections in scope: manifest file and its base directory under eduni/.
    private let sections: [(manifest: String, directory: String)] = [
        ("errata-2e/errata2e.xml", "errata-2e"),
        ("errata-3e/errata3e.xml", "errata-3e"),
        ("errata-4e/errata4e.xml", "errata-4e"),
        ("namespaces/1.0/rmt-ns10.xml", "namespaces/1.0"),
        ("namespaces/errata-1e/errata1e.xml", "namespaces/errata-1e"),
        ("misc/ht-bh.xml", "misc"),
    ]

    /// not-wf cases this implementation knowingly accepts, two classes:
    /// the namespace constraints not yet enforced (reserved prefixes and
    /// namespace names, duplicate expanded-name attributes, NCName rules)
    /// and encoding-declaration mismatches the byte decoder does not yet
    /// reject (a declared encoding contradicting the actual bytes or BOM).
    /// Both classes are tracked as their own issues under #121.
    private let knownNotWFAccepted: Set<String> = [
        // Namespace constraints.
        "namespaces/1.0/009.xml", "namespaces/1.0/010.xml", "namespaces/1.0/011.xml",
        "namespaces/1.0/012.xml", "namespaces/1.0/014.xml", "namespaces/1.0/015.xml",
        "namespaces/1.0/016.xml", "namespaces/1.0/029.xml", "namespaces/1.0/030.xml",
        "namespaces/1.0/031.xml", "namespaces/1.0/032.xml", "namespaces/1.0/033.xml",
        "namespaces/1.0/036.xml", "namespaces/1.0/042.xml", "namespaces/1.0/043.xml",
        "namespaces/1.0/044.xml", "namespaces/errata-1e/NE13a.xml", "namespaces/errata-1e/NE13b.xml",
        // Encoding-declaration mismatches.
        "errata-2e/E38.xml", "errata-2e/E61.xml", "misc/007.xml", "misc/008.xml",
    ]

    /// valid cases this implementation knowingly fails, two classes: the
    /// grapheme-cluster lexing limitation (a combining mark directly after an
    /// ASCII delimiter merges into one Swift Character, so scalar-level 5e
    /// name characters are mis-lexed; its own issue under #121) and E18,
    /// which needs per-entity base-URI tracking for nested external entities.
    private let knownValidFailures: Set<String> = [
        "errata-2e/E18.xml",
        "errata-4e/ibm04v01.xml", "errata-4e/ibm05v03.xml", "errata-4e/ibm07v01.xml",
        "errata-4e/ibm85n107.xml", "errata-4e/ibm85n114.xml", "errata-4e/ibm85n119.xml",
        "errata-4e/ibm85n121.xml", "errata-4e/ibm85n122.xml", "errata-4e/ibm85n136.xml",
        "errata-4e/ibm85n137.xml", "errata-4e/ibm85n45.xml", "errata-4e/ibm85n50.xml",
        "errata-4e/ibm85n51.xml", "errata-4e/ibm85n52.xml", "errata-4e/ibm85n53.xml",
        "errata-4e/ibm85n54.xml", "errata-4e/ibm85n63.xml", "errata-4e/ibm85n73.xml",
        "errata-4e/ibm85n74.xml", "errata-4e/ibm85n76.xml", "errata-4e/ibm85n89.xml",
        "errata-4e/ibm85n91.xml", "errata-4e/ibm86n04.xml", "errata-4e/ibm87n60.xml",
    ]

    /// invalid cases where this implementation knowingly reports no validity
    /// error (none); 140.xml is carried here because it cannot parse yet (the
    /// grapheme-cluster lexing class: its element name is a combining mark).
    private let knownInvalidAccepted: Set<String> = [
        "errata-4e/140.xml",
    ]

    private struct ManifestCase {
        let id: String
        let type: String
        let uri: String
        let editions: String?
    }

    private func manifest(_ file: String, in eduni: String) throws -> [ManifestCase] {
        var source = try String(contentsOfFile: eduni + "/" + file, encoding: .utf8)
        if source.hasPrefix("<?xml"), let declarationEnd = source.range(of: "?>") {
            source = String(source[declarationEnd.upperBound...])
        }
        let document = try PureXML.parse("<TESTS>\(source)</TESTS>")
        return try PureXML.xpath("//TEST", over: document).compactMap { selection in
            guard let element = selection.element else { return nil }
            func attribute(_ name: String) -> String? {
                element.attributes.first { $0.name.description == name }?.value
            }
            guard let id = attribute("ID"), let type = attribute("TYPE"), let uri = attribute("URI") else {
                return nil
            }
            return ManifestCase(id: id, type: type, uri: uri, editions: attribute("EDITION"))
        }
    }

    /// Whether a case applies to the Fifth Edition this package implements.
    private func appliesToFifthEdition(_ testCase: ManifestCase) -> Bool {
        guard let editions = testCase.editions else { return true }
        return editions.split(separator: " ").contains("5")
    }

    private func resolver(directory: String) -> PureXML.Parsing.EntityResolver {
        @Sendable func load(_ id: PureXML.Parsing.ExternalID) -> String? {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: directory + "/" + id.systemID)) else {
                return nil
            }
            return try? PureXML.Parsing.ByteDecoder.decode([UInt8](data))
        }
        return PureXML.Parsing.EntityResolver(
            resolveEntity: { _, id in load(id) },
            resolveExternalSubset: { id in load(id) },
        )
    }

    private func caseDirectory(_ base: String, uri: String) -> String {
        guard let slash = uri.lastIndex(of: "/") else { return base }
        return base + "/" + String(uri.prefix(upTo: slash))
    }

    private func validate(_ uri: String, in base: String) throws -> [PureXML.Validation.ValidationError] {
        let data = try Data(contentsOf: URL(fileURLWithPath: base + "/" + uri))
        let source = try PureXML.Parsing.ByteDecoder.decode([UInt8](data))
        return try PureXML.validateAgainstInternalDTD(
            source,
            limits: .init(allowDoctype: true),
            strict: true,
            resolver: resolver(directory: caseDirectory(base, uri: uri)),
        )
    }

    @Test("Every eduni not-wf case is rejected by the strict parser")
    func test_notWellFormedRejected() throws {
        guard let root else {
            return // Opt-in: suite not present.
        }
        let eduni = root + "/eduni"
        var unexpectedlyAccepted: [String] = []
        for section in sections {
            let base = eduni + "/" + section.directory
            for testCase in try manifest(section.manifest, in: eduni) {
                guard testCase.type == "not-wf", appliesToFifthEdition(testCase) else { continue }
                let key = section.directory + "/" + testCase.uri
                guard !knownNotWFAccepted.contains(key) else { continue }
                if (try? validate(testCase.uri, in: base)) != nil {
                    unexpectedlyAccepted.append(key)
                }
            }
        }
        #expect(unexpectedlyAccepted.isEmpty, "accepted \(unexpectedlyAccepted.count) not-wf cases: \(unexpectedlyAccepted)")
    }

    @Test("Every eduni valid case parses and validates cleanly")
    func test_validCleans() throws {
        guard let root else {
            return // Opt-in: suite not present.
        }
        let eduni = root + "/eduni"
        var failures: [String: String] = [:]
        for section in sections {
            let base = eduni + "/" + section.directory
            for testCase in try manifest(section.manifest, in: eduni) {
                guard testCase.type == "valid", appliesToFifthEdition(testCase) else { continue }
                let key = section.directory + "/" + testCase.uri
                guard !knownValidFailures.contains(key) else { continue }
                do {
                    if let first = try validate(testCase.uri, in: base).first {
                        failures[key] = String(describing: first)
                    }
                } catch {
                    failures[key] = String(describing: error)
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.count) valid cases failed: \(failures)")
    }

    @Test("Every eduni invalid case parses but reports a validity error")
    func test_invalidReports() throws {
        guard let root else {
            return // Opt-in: suite not present.
        }
        let eduni = root + "/eduni"
        var silentlyClean: [String] = []
        var parseFailures: [String: String] = [:]
        for section in sections {
            let base = eduni + "/" + section.directory
            for testCase in try manifest(section.manifest, in: eduni) {
                guard testCase.type == "invalid", appliesToFifthEdition(testCase) else { continue }
                let key = section.directory + "/" + testCase.uri
                guard !knownInvalidAccepted.contains(key) else { continue }
                do {
                    if try validate(testCase.uri, in: base).isEmpty {
                        silentlyClean.append(key)
                    }
                } catch {
                    parseFailures[key] = String(describing: error)
                }
            }
        }
        #expect(parseFailures.isEmpty, "\(parseFailures.count) invalid cases failed to parse: \(parseFailures)")
        #expect(silentlyClean.isEmpty, "\(silentlyClean.count) invalid cases validated clean: \(silentlyClean)")
    }
}
