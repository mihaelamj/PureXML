import Foundation
@testable import PureXML
import Testing

/// Opt-in runner for the W3C XML Conformance Test Suite's OASIS/NIST section.
/// The suite's license permits redistribution only as the unmodified archive,
/// so it is never vendored into this repository: download `xmlts` from w3.org,
/// extract it, and point `XMLCONF_ROOT` at the extracted `xmlconf` directory
/// to run. Without the variable the suite is skipped. The section's own
/// manifest (`oasis/oasis.xml`) is parsed with PureXML itself and drives the
/// case classification: `valid` and `invalid` documents must parse (invalid
/// means well-formed but DTD-invalid, which a parser must accept), `not-wf`
/// documents must be rejected, and the single `error` case is optional
/// behavior by definition and is skipped. Foundation is used here for file
/// access only; the library target remains Foundation-free.
@Suite("W3C oasis conformance (opt-in via XMLCONF_ROOT)")
struct W3COasisSuiteTests {
    private var root: String? {
        ProcessInfo.processInfo.environment["XMLCONF_ROOT"]
    }

    /// Cases the suite marks not-well-formed that this implementation
    /// knowingly accepts. The baseline is exact: any regression in the cases
    /// that DO get rejected is still caught.
    private let knownNotWFAccepted: Set<String> = []

    /// `valid`/`invalid` cases this implementation knowingly rejects.
    private let knownPassRejected: Set<String> = []

    private struct ManifestCase {
        let id: String
        let type: String
        let uri: String
        let namespaceAware: Bool
    }

    private func manifest(in directory: String) throws -> [ManifestCase] {
        let source = try String(contentsOfFile: directory + "/oasis.xml", encoding: .utf8)
        let document = try PureXML.parse(source)
        return try PureXML.xpath("//TEST", over: document).compactMap { selection in
            guard let element = selection.element else { return nil }
            func attribute(_ name: String) -> String? {
                element.attributes.first { $0.name.description == name }?.value
            }
            guard let id = attribute("ID"), let type = attribute("TYPE"), let uri = attribute("URI") else {
                return nil
            }
            return ManifestCase(id: id, type: type, uri: uri, namespaceAware: attribute("NAMESPACE") != "no")
        }
    }

    private func limits() -> PureXML.Parsing.Limits {
        PureXML.Parsing.Limits(allowDoctype: true)
    }

    /// Resolves relative SYSTEM identifiers against the case's directory, so
    /// cases with external DTD files load their siblings.
    private func resolver(directory: String) -> PureXML.Parsing.EntityResolver {
        PureXML.Parsing.EntityResolver(
            resolveEntity: { _, id in
                (try? String(contentsOfFile: directory + "/" + id.systemID, encoding: .utf8))
            },
            resolveExternalSubset: { id in
                (try? String(contentsOfFile: directory + "/" + id.systemID, encoding: .utf8))
            },
        )
    }

    /// Reads a case's raw bytes and decodes through PureXML's own byte
    /// decoder (a decode failure counts as rejection for not-wf cases).
    private func parse(file: String, in directory: String) throws -> PureXML.Model.Node {
        let data = try Data(contentsOf: URL(fileURLWithPath: directory + "/" + file))
        let source = try PureXML.Parsing.ByteDecoder.decode([UInt8](data))
        return try PureXML.parse(source, limits: limits(), resolver: resolver(directory: directory))
    }

    @Test("Every oasis not-wf case is rejected by the strict parser")
    func test_notWellFormedRejected() throws {
        guard let root else {
            return // Opt-in: suite not present.
        }
        let directory = root + "/oasis"
        var unexpectedlyAccepted: [String] = []
        for testCase in try manifest(in: directory) where testCase.type == "not-wf" {
            guard !knownNotWFAccepted.contains(testCase.uri) else { continue }
            if (try? parse(file: testCase.uri, in: directory)) != nil {
                unexpectedlyAccepted.append(testCase.uri)
            }
        }
        #expect(unexpectedlyAccepted.isEmpty, "accepted \(unexpectedlyAccepted.count) not-wf cases: \(unexpectedlyAccepted)")
    }

    @Test("Every oasis valid and invalid case parses (both are well-formed)")
    func test_wellFormedParses() throws {
        guard let root else {
            return // Opt-in: suite not present.
        }
        let directory = root + "/oasis"
        var failures: [String: String] = [:]
        for testCase in try manifest(in: directory) where testCase.type == "valid" || testCase.type == "invalid" {
            // NAMESPACE='no' cases use pre-namespace names (colons in arbitrary
            // positions); PureXML is namespace-aware, like libxml2's default
            // mode, so the manifest's own flag excludes them.
            guard testCase.namespaceAware, !knownPassRejected.contains(testCase.uri) else { continue }
            do {
                _ = try parse(file: testCase.uri, in: directory)
            } catch {
                failures[testCase.uri] = String(describing: error)
            }
        }
        #expect(failures.isEmpty, "\(failures.count) well-formed cases failed: \(failures)")
    }
}
