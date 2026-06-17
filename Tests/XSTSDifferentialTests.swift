import Foundation
@testable import PureXML
import Testing

/// Differential schema-validity harness (production-readiness stopper #3:
/// correctness must be characterised against an independent reference, not just a
/// finite labelled suite). For every `.xsd` under `XSTS_ROOT` it compares
/// PureXML's compile verdict with libxml2's (`xmllint --schema`) and writes the
/// disagreements to /tmp/xsts-differential.txt for triage. Opt-in (needs
/// `XSTS_ROOT` and `/usr/bin/xmllint`); never runs in plain `swift test` or CI.
///
/// IMPORTANT, established by triage: libxml2 is the LENIENT party. "PureXML
/// rejects, libxml2 accepts" is overwhelmingly PureXML being *more* correct --
/// enforcing facet consistency (minLength ≤ maxLength), fractionDigits ≤ base,
/// Element Declarations Consistent, whiteSpace restriction, au-props-correct, and
/// notation rules that libxml2 does not. So that direction is NOT a false-positive
/// signal and is not asserted on. The actionable direction for PureXML is the
/// OTHER one -- "PureXML accepts, libxml2 rejects" -- a triage queue of candidate
/// false negatives (stopper #2), each to be confirmed against the spec (libxml2
/// can also be over-strict) before fixing. The authoritative false-positive gate
/// remains the XSTS suite's W3C-labelled `valid-schemas-rejected` (== 0).
///
/// xmllint and the corpus are used only in this test harness; neither is a
/// dependency of the shipped package.
@Suite("Schema-validity differential vs libxml2 (opt-in via XSTS_ROOT)")
struct XSTSDifferentialTests {
    private var root: String? {
        ProcessInfo.processInfo.environment["XSTS_ROOT"]
    }

    @Test("Characterise PureXML schema validity against libxml2")
    func test_differential() {
        guard let root, xmllintAvailable() else { return } // Opt-in.
        let schemas = xsdFiles(under: root + "/msData")
        var agreeValid = 0, agreeInvalid = 0
        var pureRejectsRefAccepts: [String] = []
        var pureAcceptsRefRejects: [String] = []

        for path in schemas {
            guard let source = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let directory = (path as NSString).deletingLastPathComponent
            let loader: (String) -> String? = { location in
                try? String(contentsOfFile: (directory as NSString).appendingPathComponent(location), encoding: .utf8)
            }
            let pureValid = (try? PureXML.Schema.Document(source, schemaLoader: loader)) != nil
            guard let refValid = xmllintSchemaValid(path) else { continue } // skip if xmllint errored opaquely
            switch (pureValid, refValid) {
            case (true, true): agreeValid += 1
            case (false, false): agreeInvalid += 1
            case (false, true): pureRejectsRefAccepts.append(name(path))
            case (true, false): pureAcceptsRefRejects.append(name(path))
            }
        }

        let report = """
        differential vs libxml2 over \(schemas.count) schemas:
          agree valid:   \(agreeValid)
          agree invalid: \(agreeInvalid)
          PureXML stricter (rejects, libxml2 accepts; mostly PureXML-correct): \(pureRejectsRefAccepts.count)
          libxml2 stricter (PureXML accepts, libxml2 rejects; false-negative triage queue): \(pureAcceptsRefRejects.count)
        """
        FileHandle.standardError.write(Data((report + "\n").utf8))
        let lines = ["PureXML stricter than libxml2 (triage shows these are largely PureXML-correct):"]
            + pureRejectsRefAccepts.sorted().map { "  " + $0 }
            + ["", "libxml2 stricter than PureXML (candidate false negatives for stopper #2; confirm vs spec):"]
            + pureAcceptsRefRejects.sorted().map { "  " + $0 }
        try? lines.joined(separator: "\n").write(toFile: "/tmp/xsts-differential.txt", atomically: true, encoding: .utf8)

        // This is a characterisation tool: libxml2 is not ground truth (it is
        // lenient in one direction and can be over-strict in the other), so neither
        // disagreement count is a pass/fail correctness gate -- the report is the
        // deliverable. The only invariant asserted is that the harness actually ran
        // over a meaningful corpus and produced data to triage.
        #expect(agreeValid + agreeInvalid > 1000, "differential did not run over a meaningful corpus")
    }

    // MARK: - libxml2 oracle

    private func xmllintAvailable() -> Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/xmllint")
    }

    /// libxml2's schema-validity verdict for one `.xsd`, or nil if it could not be
    /// determined. The schema is loaded via `--schema`; a compile failure prints
    /// `Schemas parser error` / `failed to compile`. The instance (`/dev/null`,
    /// empty) always fails to parse, which is ignored -- only schema-compile errors
    /// count toward schema validity.
    private func xmllintSchemaValid(_ path: String) -> Bool? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xmllint")
        process.arguments = ["--noout", "--schema", path, "/dev/null"]
        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = Pipe()
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        if output.contains("Schemas parser error") || output.contains("failed to compile") { return false }
        return true
    }

    private func xsdFiles(under directory: String) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: directory) else { return [] }
        var result: [String] = []
        for case let relative as String in enumerator where relative.hasSuffix(".xsd") {
            result.append((directory as NSString).appendingPathComponent(relative))
        }
        return result.sorted()
    }

    private func name(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}
