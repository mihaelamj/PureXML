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

    /// not-wf cases this implementation knowingly accepts (none).
    private let knownNotWFAccepted: Set<String> = []

    /// valid cases this implementation knowingly fails (none).
    private let knownValidFailures: Set<String> = []

    /// invalid cases where this implementation knowingly reports no validity
    /// error (none).
    private let knownInvalidAccepted: Set<String> = []

    private struct ManifestCase {
        let id: String
        let type: String
        let uri: String
        let editions: String?
        let namespaceAware: Bool
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
            return ManifestCase(
                id: id,
                type: type,
                uri: uri,
                editions: attribute("EDITION"),
                namespaceAware: attribute("NAMESPACE") != "no",
            )
        }
    }

    /// Whether a case applies to this implementation: the Fifth Edition, and
    /// namespace-aware processing (NAMESPACE='no' cases use pre-namespace
    /// colons in names, which a namespace-aware parser correctly refuses).
    private func appliesToFifthEdition(_ testCase: ManifestCase) -> Bool {
        guard testCase.namespaceAware else { return false }
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
