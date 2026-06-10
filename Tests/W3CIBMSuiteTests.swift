import Foundation
@testable import PureXML
import Testing

/// Opt-in runner for the W3C XML Conformance Test Suite's IBM section, the
/// deepest block: per-production directories covering valid, invalid, and
/// not-wf cases with heavy DTD usage. Classification follows the Sun model:
/// `valid` must parse and DTD-validate cleanly (strict mode), `invalid` must
/// parse but report at least one validity error, `not-wf` must be rejected.
/// Point `XMLCONF_ROOT` at the extracted `xmlconf` directory to run (the
/// suite is never vendored; its license permits redistribution only as the
/// unmodified archive). The `xml-1.1` subdirectory is out of scope: PureXML
/// targets XML 1.0 Fifth Edition. Foundation is used for file access only.
@Suite("W3C ibm conformance (opt-in via XMLCONF_ROOT)")
struct W3CIBMSuiteTests {
    private var root: String? {
        ProcessInfo.processInfo.environment["XMLCONF_ROOT"]
    }

    /// not-wf cases this implementation knowingly accepts: both are
    /// parameter-entity references inside internal-subset markup declarations,
    /// which this package supports as a feature (the xmltest 160-162 class;
    /// the strict profile of #128 will reject them).
    private let knownNotWFAccepted: Set<String> = [
        "not-wf/P29/ibm29n03.xml", "not-wf/P29/ibm29n04.xml",
    ]

    /// Productions 85-89 are the 1998 character-class appendices (BaseChar,
    /// Ideographic, CombiningChar, Digit, Extender), deleted by XML 1.0 Fifth
    /// Edition, whose Name productions this package implements; the characters
    /// these cases reject became legal (the xmltest 141 class). The count is
    /// asserted exactly so a regression in either direction is caught.
    private let preFifthEditionCaseCount = 279

    private func isPreFifthEditionCharacterClass(_ uri: String) -> Bool {
        (85 ... 89).contains { uri.hasPrefix("not-wf/P\($0)/") }
    }

    /// valid cases this implementation knowingly fails (parse or validation).
    private let knownValidFailures: Set<String> = []

    /// invalid cases where this implementation knowingly reports no validity
    /// error.
    private let knownInvalidAccepted: Set<String> = []

    private struct ManifestCase {
        let id: String
        let uri: String
    }

    /// Reads one manifest (a fragment with multiple TESTCASES roots), wrapped
    /// before parsing with PureXML itself.
    private func manifest(_ file: String, in directory: String) throws -> [ManifestCase] {
        let source = try String(contentsOfFile: directory + "/" + file, encoding: .utf8)
        let document = try PureXML.parse("<TESTS>\(source)</TESTS>")
        return try PureXML.xpath("//TEST", over: document).compactMap { selection in
            guard let element = selection.element else { return nil }
            func attribute(_ name: String) -> String? {
                element.attributes.first { $0.name.description == name }?.value
            }
            guard let id = attribute("ID"), let uri = attribute("URI") else { return nil }
            return ManifestCase(id: id, uri: uri)
        }
    }

    private func limits() -> PureXML.Parsing.Limits {
        PureXML.Parsing.Limits(allowDoctype: true)
    }

    /// Resolves relative SYSTEM identifiers against the case's own directory,
    /// byte-decoding through PureXML's own decoder.
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

    private func caseDirectory(_ section: String, uri: String) -> String {
        guard let slash = uri.lastIndex(of: "/") else { return section }
        return section + "/" + String(uri.prefix(upTo: slash))
    }

    private func source(of uri: String, in section: String) throws -> String {
        let data = try Data(contentsOf: URL(fileURLWithPath: section + "/" + uri))
        return try PureXML.Parsing.ByteDecoder.decode([UInt8](data))
    }

    @Test("Every ibm not-wf case is rejected by the strict parser")
    func test_notWellFormedRejected() throws {
        guard let root else {
            return // Opt-in: suite not present.
        }
        let section = root + "/ibm"
        var unexpectedlyAccepted: [String] = []
        var fifthEditionAccepted = 0
        for testCase in try manifest("ibm_oasis_not-wf.xml", in: section) where !knownNotWFAccepted.contains(testCase.uri) {
            let directory = caseDirectory(section, uri: testCase.uri)
            let accepted = (try? PureXML.parse(
                source(of: testCase.uri, in: section),
                limits: limits(),
                resolver: resolver(directory: directory),
            )) != nil
            if accepted {
                if isPreFifthEditionCharacterClass(testCase.uri) {
                    fifthEditionAccepted += 1
                } else {
                    unexpectedlyAccepted.append(testCase.uri)
                }
            }
        }
        #expect(unexpectedlyAccepted.isEmpty, "accepted \(unexpectedlyAccepted.count) not-wf cases: \(unexpectedlyAccepted)")
        #expect(fifthEditionAccepted == preFifthEditionCaseCount, "pre-5e class drifted: \(fifthEditionAccepted)")
    }

    @Test("Every ibm valid case parses and validates cleanly against its DTD")
    func test_validCleans() throws {
        guard let root else {
            return // Opt-in: suite not present.
        }
        let section = root + "/ibm"
        var failures: [String: String] = [:]
        for testCase in try manifest("ibm_oasis_valid.xml", in: section) where !knownValidFailures.contains(testCase.uri) {
            let directory = caseDirectory(section, uri: testCase.uri)
            do {
                let errors = try PureXML.validateAgainstInternalDTD(
                    source(of: testCase.uri, in: section),
                    limits: limits(),
                    strict: true,
                    resolver: resolver(directory: directory),
                )
                if let first = errors.first {
                    failures[testCase.uri] = String(describing: first)
                }
            } catch {
                failures[testCase.uri] = String(describing: error)
            }
        }
        #expect(failures.isEmpty, "\(failures.count) valid cases failed: \(failures)")
    }

    @Test("Every ibm invalid case parses but reports a validity error")
    func test_invalidReports() throws {
        guard let root else {
            return // Opt-in: suite not present.
        }
        let section = root + "/ibm"
        var silentlyClean: [String] = []
        var parseFailures: [String: String] = [:]
        for testCase in try manifest("ibm_oasis_invalid.xml", in: section) where !knownInvalidAccepted.contains(testCase.uri) {
            let directory = caseDirectory(section, uri: testCase.uri)
            do {
                let errors = try PureXML.validateAgainstInternalDTD(
                    source(of: testCase.uri, in: section),
                    limits: limits(),
                    strict: true,
                    resolver: resolver(directory: directory),
                )
                if errors.isEmpty {
                    silentlyClean.append(testCase.uri)
                }
            } catch {
                parseFailures[testCase.uri] = String(describing: error)
            }
        }
        #expect(parseFailures.isEmpty, "\(parseFailures.count) invalid (well-formed) cases failed to parse: \(parseFailures)")
        #expect(silentlyClean.isEmpty, "\(silentlyClean.count) invalid cases validated clean: \(silentlyClean)")
    }
}
