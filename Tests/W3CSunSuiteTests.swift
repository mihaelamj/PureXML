import Foundation
@testable import PureXML
import Testing

/// Opt-in runner for the W3C XML Conformance Test Suite's Sun section, the
/// first section to exercise the validity layer: `valid` documents must parse
/// AND validate cleanly against their DTDs, `invalid` documents are
/// well-formed but must produce at least one validity error, and `not-wf`
/// documents must be rejected by the strict parser. Point `XMLCONF_ROOT` at
/// the extracted `xmlconf` directory to run (the suite is never vendored; its
/// license permits redistribution only as the unmodified archive). The
/// section's manifests are rootless fragments designed for entity inclusion,
/// so they are wrapped in a synthetic root before being parsed with PureXML.
/// Foundation is used here for file access only.
@Suite("W3C sun conformance (opt-in via XMLCONF_ROOT)")
struct W3CSunSuiteTests {
    private var root: String? {
        ProcessInfo.processInfo.environment["XMLCONF_ROOT"]
    }

    /// not-wf cases this implementation knowingly accepts, the current
    /// frontier (exact, so any regression is caught): not-sa03 needs the
    /// standalone='yes' entity-declared WFC.
    private let knownNotWFAccepted: Set<String> = [
        "not-wf/not-sa03.xml",
    ]

    /// valid cases this implementation knowingly fails: both need general-
    /// entity replacement text containing markup to be reparsed into elements
    /// rather than included as character data (tracked as its own issue).
    private let knownValidFailures: Set<String> = [
        "valid/pe03.xml", "valid/ext02.xml",
    ]

    /// invalid cases where this implementation knowingly reports no validity
    /// error yet, the validity-layer frontier this issue works down: the
    /// standalone VCs (not-sa*), ID/IDREF corners, #REQUIRED enforcement,
    /// per-type attribute VCs (attr*), the root-element/DOCTYPE name match,
    /// EMPTY content, and UTF-16 cases.
    private let knownInvalidAccepted: Set<String> = [
        "invalid/dtd01.xml", "invalid/dtd02.xml", "invalid/el01.xml",
        "invalid/el04.xml", "invalid/el05.xml", "invalid/id01.xml",
        "invalid/id03.xml", "invalid/id04.xml", "invalid/id05.xml",
        "invalid/not-sa01.xml", "invalid/not-sa02.xml", "invalid/not-sa04.xml",
        "invalid/not-sa05.xml", "invalid/not-sa06.xml", "invalid/not-sa07.xml",
        "invalid/not-sa08.xml", "invalid/not-sa09.xml", "invalid/not-sa10.xml",
        "invalid/not-sa11.xml", "invalid/not-sa12.xml", "invalid/not-sa13.xml",
        "invalid/not-sa14.xml", "invalid/required01.xml", "invalid/required02.xml",
        "invalid/root.xml", "invalid/attr04.xml", "invalid/attr09.xml",
        "invalid/attr10.xml", "invalid/attr11.xml", "invalid/attr12.xml",
        "invalid/attr13.xml", "invalid/attr14.xml", "invalid/attr15.xml",
        "invalid/attr16.xml", "invalid/utf16b.xml", "invalid/utf16l.xml",
        "invalid/empty.xml",
    ]

    private struct ManifestCase {
        let id: String
        let uri: String
    }

    /// Reads one manifest fragment (`sun-valid.xml` and friends): the fragment
    /// has no single root, so it is wrapped before parsing.
    private func manifest(_ file: String, in directory: String) throws -> [ManifestCase] {
        var source = try String(contentsOfFile: directory + "/" + file, encoding: .utf8)
        if let declarationEnd = source.range(of: "?>") {
            source = String(source[declarationEnd.upperBound...])
        }
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
    /// byte-decoding through PureXML's own decoder so UTF-16 entity files work.
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

    @Test("Every sun not-wf case is rejected by the strict parser")
    func test_notWellFormedRejected() throws {
        guard let root else {
            return // Opt-in: suite not present.
        }
        let section = root + "/sun"
        var unexpectedlyAccepted: [String] = []
        for testCase in try manifest("sun-not-wf.xml", in: section) where !knownNotWFAccepted.contains(testCase.uri) {
            let directory = caseDirectory(section, uri: testCase.uri)
            let accepted = (try? PureXML.parse(
                source(of: testCase.uri, in: section),
                limits: limits(),
                resolver: resolver(directory: directory),
            )) != nil
            if accepted {
                unexpectedlyAccepted.append(testCase.uri)
            }
        }
        #expect(unexpectedlyAccepted.isEmpty, "accepted \(unexpectedlyAccepted.count) not-wf cases: \(unexpectedlyAccepted)")
    }

    @Test("Every sun valid case parses and validates cleanly against its DTD")
    func test_validCleans() throws {
        guard let root else {
            return // Opt-in: suite not present.
        }
        let section = root + "/sun"
        var failures: [String: String] = [:]
        for testCase in try manifest("sun-valid.xml", in: section) where !knownValidFailures.contains(testCase.uri) {
            let directory = caseDirectory(section, uri: testCase.uri)
            do {
                let errors = try PureXML.validateAgainstInternalDTD(
                    source(of: testCase.uri, in: section),
                    limits: limits(),
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

    @Test("Every sun invalid case parses but reports a validity error")
    func test_invalidReports() throws {
        guard let root else {
            return // Opt-in: suite not present.
        }
        let section = root + "/sun"
        var silentlyClean: [String] = []
        var parseFailures: [String: String] = [:]
        for testCase in try manifest("sun-invalid.xml", in: section) where !knownInvalidAccepted.contains(testCase.uri) {
            let directory = caseDirectory(section, uri: testCase.uri)
            do {
                let errors = try PureXML.validateAgainstInternalDTD(
                    source(of: testCase.uri, in: section),
                    limits: limits(),
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
