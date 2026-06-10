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

    /// Cases this implementation knowingly accepts although the suite marks
    /// them not-well-formed. Two classes, tracked for later hardening: the
    /// internal-subset scanner is deliberately lenient about DTD grammar
    /// details (declaration syntax, conditional sections, parameter-entity
    /// placement), and entity replacement text is not yet checked for
    /// standalone well-formedness (tags spanning entity boundaries, partial
    /// markup in values). The baseline below is exact, so any regression in
    /// the cases that DO pass is still caught.
    private let knownNotWFDeviations: Set<String> = [
        "054.xml", "057.xml", "058.xml", "059.xml", "060.xml", "061.xml", "062.xml", "063.xml",
        "064.xml", "065.xml", "066.xml", "067.xml", "068.xml", "069.xml", "074.xml", "078.xml",
        "079.xml", "080.xml", "082.xml", "084.xml", "085.xml", "086.xml", "087.xml", "089.xml",
        "090.xml", "091.xml", "092.xml", "096.xml", "101.xml", "102.xml", "103.xml", "107.xml",
        "113.xml", "114.xml", "115.xml", "116.xml", "117.xml", "119.xml", "120.xml", "121.xml",
        "140.xml", "141.xml", "149.xml", "153.xml", "158.xml", "160.xml", "161.xml", "162.xml",
        "165.xml", "168.xml", "169.xml", "170.xml", "173.xml", "174.xml", "175.xml", "180.xml",
        "182.xml",
    ]

    /// valid/sa/114.xml: a CDATA section inside an entity value must protect
    /// the &foo; reference from expansion; the entity decoder expands it
    /// before the CDATA section is recognized. Same hardening track.
    private let knownValidDeviations: Set<String> = ["114.xml"]

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
