import Foundation
@testable import PureXML
import Testing

/// Opt-in runner for the W3C XML Conformance Test Suite's japanese section:
/// the same prose encoded as UTF-8, UTF-16 (both orders), Shift_JIS, EUC-JP,
/// and ISO-2022-JP, with moderately complex parameter-entity DTDs. The
/// optional encodings are classified TYPE='error' (a processor either
/// supports them or reports a fatal error); PureXML ships all of them, so
/// every case must parse and DTD-validate cleanly. Point `XMLCONF_ROOT` at
/// the extracted `xmlconf` directory to run (the suite is never vendored).
/// Foundation is used for file access only.
@Suite("W3C japanese conformance (opt-in via XMLCONF_ROOT)")
struct W3CJapaneseSuiteTests {
    private var root: String? {
        ProcessInfo.processInfo.environment["XMLCONF_ROOT"]
    }

    /// Cases this implementation knowingly fails.
    private let knownFailures: Set<String> = []

    private func manifest(in directory: String) throws -> [String] {
        var source = try String(contentsOfFile: directory + "/japanese.xml", encoding: .utf8)
        if source.hasPrefix("<?xml"), let declarationEnd = source.range(of: "?>") {
            source = String(source[declarationEnd.upperBound...])
        }
        let document = try PureXML.parse("<TESTS>\(source)</TESTS>")
        return try PureXML.xpath("//TEST", over: document).compactMap { selection in
            selection.element?.attributes.first { $0.name.description == "URI" }?.value
        }
    }

    /// Resolves sibling DTD files through PureXML's own byte decoder, since
    /// the DTDs themselves are in the document's encoding.
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

    @Test("Every japanese case decodes, parses, and validates cleanly")
    func test_allCasesParse() throws {
        guard let root else {
            return // Opt-in: suite not present.
        }
        let directory = root + "/japanese"
        var failures: [String: String] = [:]
        for uri in try manifest(in: directory) where !knownFailures.contains(uri) {
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: directory + "/" + uri))
                let source = try PureXML.Parsing.ByteDecoder.decode([UInt8](data))
                let errors = try PureXML.validateAgainstInternalDTD(
                    source,
                    limits: .init(allowDoctype: true),
                    resolver: resolver(directory: directory),
                )
                if let first = errors.first {
                    failures[uri] = String(describing: first)
                }
            } catch {
                failures[uri] = String(describing: error)
            }
        }
        #expect(failures.isEmpty, "\(failures.count) japanese cases failed: \(failures)")
    }
}
