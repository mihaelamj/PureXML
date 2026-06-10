import Foundation
@testable import PureXML
import Testing

/// Opt-in runner for the W3C XML Conformance Test Suite's xmltest section
/// (James Clark's cases). The suite's license permits redistribution only as
/// the unmodified archive, so it is never vendored into this repository:
/// download `xmlts` from w3.org, extract it, and point `XMLTS_ROOT` at the
/// `xmlconf/xmltest` directory to run. Without the variable the suite is
/// skipped. Foundation is used here for file access only; this is a test-only
/// dependency and the library target remains Foundation-free.
@Suite("W3C xmltest conformance (opt-in via XMLTS_ROOT)")
struct W3CXMLSuiteTests {
    private var root: String? {
        ProcessInfo.processInfo.environment["XMLTS_ROOT"]
    }

    /// The five cases this implementation knowingly accepts although the suite
    /// marks them not-well-formed, all deliberate: 063 (conditional sections in
    /// the internal subset) and 160-162 (parameter-entity references in the
    /// internal subset) are extensions this package supports as features, and
    /// 141 expects the 1998 suite's name-character classes where this package
    /// implements XML 1.0 Fifth Edition's (U+0E5C is a name character there).
    /// The baseline is exact, so any regression in the 181 cases that DO pass
    /// is still caught.
    private let knownNotWFDeviations: Set<String> = [
        "063.xml", "141.xml", "160.xml", "161.xml", "162.xml",
    ]

    /// valid/sa/012.xml is flagged NAMESPACE='no' by the suite's own
    /// manifest: it declares an attribute named ':', a pre-namespace XML 1.0
    /// Name that a namespace-aware parser correctly refuses.
    private let knownValidDeviations: Set<String> = ["012.xml"]

    private func files(in directory: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory)
            .filter { $0.hasSuffix(".xml") }
            .sorted()
    }

    private func limits() -> PureXML.Parsing.Limits {
        PureXML.Parsing.Limits(allowDoctype: true)
    }

    /// Resolves relative SYSTEM identifiers against the case's directory, so the
    /// suite's external-entity cases load their sibling `.ent` files.
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

    /// Reads a case's raw bytes and decodes through PureXML's own byte decoder,
    /// since the suite deliberately includes UTF-16 documents and broken
    /// encodings (a decode failure counts as rejection for not-wf cases).
    private func parse(file: String, in directory: String) throws -> PureXML.Model.Node {
        let data = try Data(contentsOf: URL(fileURLWithPath: directory + "/" + file))
        let source = try PureXML.Parsing.ByteDecoder.decode([UInt8](data))
        return try PureXML.parse(source, limits: limits(), resolver: resolver(directory: directory))
    }

    @Test("Every not-wf/sa case is rejected by the strict parser")
    func test_notWellFormedRejected() throws {
        guard let root else {
            return // Opt-in: suite not present.
        }
        let directory = root + "/not-wf/sa"
        var unexpectedlyAccepted: [String] = []
        for file in try files(in: directory) where !knownNotWFDeviations.contains(file) {
            if (try? parse(file: file, in: directory)) != nil {
                unexpectedlyAccepted.append(file)
            }
        }
        #expect(unexpectedlyAccepted.isEmpty, "accepted \(unexpectedlyAccepted.count) not-wf cases: \(unexpectedlyAccepted)")
    }

    @Test("Every valid/sa case parses")
    func test_validParses() throws {
        guard let root else {
            return // Opt-in: suite not present.
        }
        let directory = root + "/valid/sa"
        var failures: [String: String] = [:]
        for file in try files(in: directory) where !knownValidDeviations.contains(file) {
            do {
                _ = try parse(file: file, in: directory)
            } catch {
                failures[file] = String(describing: error)
            }
        }
        #expect(failures.isEmpty, "\(failures.count) valid cases failed: \(failures)")
    }
}
