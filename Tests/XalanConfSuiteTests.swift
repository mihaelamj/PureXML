import Foundation
@testable import PureXML
import Testing

/// Opt-in runner for the Apache xalan-test XSLT 1.0 conformance corpus (the
/// de facto OASIS-era suite: per-category stylesheet/source pairs with gold
/// outputs, Apache License 2.0). Point `XALAN_TS_ROOT` at the checkout's
/// `tests` directory to run; the corpus is never vendored. Comparison
/// normalizes deliberately: a gold and an actual that both parse as XML are
/// compared by canonical form (Xalan's indentation is not normative); other
/// outputs compare with whitespace runs collapsed. Foundation is used for
/// file access only.
@Suite("Xalan XSLT conformance (opt-in via XALAN_TS_ROOT)")
struct XalanConfSuiteTests {
    private var root: String? {
        ProcessInfo.processInfo.environment["XALAN_TS_ROOT"]
    }

    /// Cases this implementation knowingly fails, kept exact in
    /// Tests/Fixtures/xalan-baseline.txt (one category/name per line): a
    /// fixed case must leave the file and a regression shows as a new
    /// failure.
    private func knownFailures() -> Set<String> {
        guard let url = Bundle.module.url(forResource: "xalan-baseline", withExtension: "txt", subdirectory: "Fixtures"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return Set(text.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("#") && !$0.isEmpty })
    }

    /// Categories that are out of scope: extension mechanisms beyond the
    /// XSLT 1.0 core that this package does not ship.
    private let outOfScopeCategories: Set<String> = []

    @Test("Every conf case transforms to its gold output")
    func test_confSuite() throws {
        guard let root else {
            return // Opt-in: suite not present.
        }
        let confDirectory = root + "/conf"
        let goldDirectory = root + "/conf-gold"
        let manager = FileManager.default
        let baseline = knownFailures()
        var failures: [String: String] = [:]
        var passed = 0
        var skippedNoGold = 0
        let categories = try manager.contentsOfDirectory(atPath: confDirectory)
            .filter { !outOfScopeCategories.contains($0) }
            .sorted()
        for category in categories {
            let categoryPath = confDirectory + "/" + category
            var isDirectory = ObjCBool(false)
            guard manager.fileExists(atPath: categoryPath, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            for sheet in try manager.contentsOfDirectory(atPath: categoryPath).filter({ $0.hasSuffix(".xsl") }).sorted() {
                let name = String(sheet.dropLast(4))
                let key = category + "/" + name
                let goldPath = goldDirectory + "/" + category + "/" + name + ".out"
                guard manager.fileExists(atPath: goldPath) else {
                    skippedNoGold += 1
                    continue
                }
                if let problem = runCase(category: category, name: name, root: root, goldPath: goldPath) {
                    failures[key] = problem
                } else {
                    passed += 1
                }
            }
        }
        try? failures.keys.sorted().joined(separator: "\n").write(toFile: "/tmp/xalan-failures.txt", atomically: true, encoding: .utf8)
        let newFailures = Set(failures.keys).subtracting(baseline).sorted()
        let fixed = baseline.subtracting(failures.keys).sorted()
        let sample = newFailures.prefix(3).map { ($0, failures[$0] ?? "") }
        let report = "passed \(passed), no-gold \(skippedNoGold), \(newFailures.count) NEW: \(newFailures.prefix(40)) :: \(sample)"
        #expect(newFailures.isEmpty, Comment(rawValue: report))
        #expect(fixed.isEmpty, "\(fixed.count) baselined cases now pass (remove from xalan-baseline.txt): \(fixed.prefix(40))")
    }

    private func runCase(category: String, name: String, root: String, goldPath: String) -> String? {
        let directory = root + "/conf/" + category
        guard let stylesheet = try? String(contentsOfFile: directory + "/" + name + ".xsl", encoding: .utf8),
              let source = try? String(contentsOfFile: directory + "/" + name + ".xml", encoding: .utf8)
        else {
            return "unreadable inputs"
        }
        guard let goldData = FileManager.default.contents(atPath: goldPath),
              let gold = (try? PureXML.Parsing.ByteDecoder.decode([UInt8](goldData))) ?? String(data: goldData, encoding: .utf8)
        else {
            return "unreadable gold"
        }
        let loader: (String) -> String? = { uri in
            (try? String(contentsOfFile: directory + "/" + uri, encoding: .utf8))
        }
        let actual: String
        do {
            actual = try PureXML.XSLT.transform(
                stylesheet: stylesheet,
                source: source,
                documentLoader: loader,
                parameters: harnessParameters(directory + "/" + name + ".param"),
            )
        } catch {
            return "transform threw: \(error)"
        }
        return Self.equivalent(actual: actual, gold: gold) ? nil : "output differs from gold"
    }

    /// The xalan harness contract: a `<case>.param` file supplies top-level
    /// parameters as `name=value` lines (comments and blanks ignored, values
    /// cut at whitespace).
    private func harnessParameters(_ path: String) -> [String: String] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [:] }
        var parameters: [String: String] = [:]
        // CRLF is one Character in Swift: split on any newline grapheme.
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), let equals = trimmed.firstIndex(of: "=") else { continue }
            let name = String(trimmed[..<equals])
            let value = trimmed[trimmed.index(after: equals)...].split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
            parameters[name] = value
        }
        return parameters
    }

    /// Gold comparison: canonical XML when both sides parse (indentation is
    /// not normative), otherwise collapsed whitespace with whitespace
    /// adjacent to tag boundaries dropped (the html method's indentation is
    /// layout, not content).
    static func equivalent(actual: String, gold: String) -> Bool {
        if let actualNode = try? PureXML.parse(actual), let goldNode = try? PureXML.parse(gold) {
            if PureXML.Canonical.canonicalize(actualNode) == PureXML.Canonical.canonicalize(goldNode) {
                return true
            }
        }
        let collapse = { (text: String) in
            var melted = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            while let range = melted.range(of: "> <") {
                melted.replaceSubrange(range, with: "><")
            }
            return melted
        }
        return collapse(actual) == collapse(gold)
    }
}
