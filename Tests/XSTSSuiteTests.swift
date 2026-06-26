import Foundation
import Testing
@testable import PureXML

/// Opt-in runner for the W3C XML Schema Test Suite (XSTS, the 2006-11-06
/// release; W3C Document License, never vendored). Point `XSTS_ROOT` at the
/// directory containing `suite.xml`. The suite nests testSet files holding
/// testGroups: a schemaTest's documents must compile when expected valid and
/// be rejected when expected invalid; each instanceTest validates against
/// the group's schema with the expected outcome. Hrefs resolve against the
/// referencing file; include/import locations resolve from disk relative to
/// the schema. Counts are asserted exactly so progress and regressions both
/// show; current failures are written to /tmp/xsts-failures.txt for the
/// burn-down. Foundation is used for file access only.
@Suite("W3C XSTS (opt-in via XSTS_ROOT)")
struct XSTSSuiteTests {
    private var root: String? {
        ProcessInfo.processInfo.environment["XSTS_ROOT"]
    }

    /// Exact-count baselines against the 2006-11-06 archive (first measured
    /// 2026-06-13, over 14383 groups), counting only tests whose expected outcome
    /// is settled: entries marked `<current status="queried">` (disputed in W3C
    /// Bugzilla, with the expected validity itself contested) are excluded, since
    /// agreeing or disagreeing with a contested expectation is not meaningful.
    /// These ratchet down as conformance work closes deviations (#145-#148); a
    /// count rising is a regression. The suite is opt-in, so CI and plain
    /// `swift test` are unaffected; run it with `swift test -c release --filter
    /// XSTS` (debug is far slower and the corpus is large). Per-case deviations
    /// are written to /tmp/xsts-failures.txt for the burn-down. The full per-step
    /// history of how each bucket reached its current value (every rule and its exact
    /// delta) lives in CHANGELOG.md and docs/xsts-deviations.md, not inline here.
    private let knownSchemaValidRejected = 0
    /// Schema bucket, per-step deltas in CHANGELOG.md. Recent: 15 -> 13, an
    /// unescaped `[` inside a pattern-facet character class is a syntax error per
    /// XSD Appendix F (RegexTest_993, RegexTest_1477); 13 -> 12, an unknown
    /// `\p{...}` category or block name is rejected now the block set is complete
    /// (reK88, `\p{IsaA0-a9}`); 12 -> 11, an attribute-wildcard union in a type
    /// extension that is not expressible per Errata E1-10 is rejected (wildZ013);
    /// 11 -> 10, a redefine self-reference's expansion is now seen by the UPA check
    /// and that check runs over every composition root, so a redefined group that
    /// duplicates a particle across the redefine chain is rejected (schN10);
    /// 10 -> 9, the attribute-use restriction check (derivation-ok-restriction.2:
    /// a base `required` attribute may not become `optional`) now also runs over a
    /// `simpleContent` restriction, not only `complexContent` (particlesZ030_d,
    /// which libxml2 also rejects).
    private let knownSchemaInvalidAccepted = 9
    private let knownInstanceValidRejected = 0
    /// Instance bucket (133 -> 22), per-step deltas in CHANGELOG.md: xsi:type must derive from the declared
    /// type; anyType cannot stand in for anySimpleType; an untyped substitutionGroup member inherits its head's
    /// type; a non-nillable element carries no xsi:nil; block/blockDefault bar substitutions (incl. an inline-
    /// typed member reached by a blocked method, disallowedSubst00105m); ur-type anyType wildcards are `lax`;
    /// identity fields compare in decimal value space (default/fixed when absent) and must be simple-content,
    /// element-children (idK012) or empty-complex (idG006); an attr wildcard is the INTERSECTION; year 0000 invalid;
    /// a nilled element may not have a fixed value constraint, cvc-elt.3.2.2 (addB065);
    /// an optional xs:all group present in the instance still requires its members (mgZ001);
    /// a defaulted/fixed IDREF/IDREFS must resolve to a matching ID, cvc-id (idZ012).
    /// 19 -> 17: a negated character-class subtraction excludes both the
    /// negated base and the subtrahend (`[^cde-[ag]]`), RegexTest_430 and _422.
    /// 17 -> 15: the attribute-wildcard union of a type extension is
    /// computed per Errata E1-10, so the resulting wildcard admits exactly the
    /// right attributes (wildZ013a, wildZ013d).
    /// Latest (15 -> 14): an `xsi:type` that reaches a union declared type through
    /// one of its members by a blocked derivation method is rejected (cvc-elt.4.3
    /// / cos-st-derived-OK 2.2.4, elemT074: `block="restriction"` on the element,
    /// the substitute restricting a union member).
    private let knownInstanceInvalidAccepted = 14
    /// Suspect instance tests excluded from the counts: the Ethiopic-digit `\d`
    /// cases contradict `\d` = `\p{Nd}` at Unicode 3.2 and are tracked as disputed.
    private static let specDivergentInstances: Set<String> = ["reS17.v", "reS38.v", "reZ004v.v"]

    @Test("Every XSTS case behaves: compile, reject, validate, invalidate")
    func test_suite() throws {
        guard let root else {
            return // Opt-in: suite not present.
        }
        var counters = Counters()
        let suite = try parsed(at: root + "/suite.xml")
        for setHref in references(in: suite, named: "testSetRef") {
            let setPath = root + "/" + setHref
            let setDirectory = directory(of: setPath)
            FileHandle.standardError.write(Data("xsts: \(setHref)\n".utf8))
            guard let testSet = try? parsed(at: setPath) else {
                counters.note("unreadable testSet \(setHref)")
                continue
            }
            for group in elements(named: "testGroup", under: testSet) {
                runGroup(group, directory: setDirectory, into: &counters)
            }
        }
        try? counters.failures.joined(separator: "\n").write(toFile: "/tmp/xsts-failures.txt", atomically: true, encoding: .utf8)
        let report = "groups \(counters.groups), schema ok \(counters.schemaAgreed), instance ok \(counters.instanceAgreed)"
        #expect(counters.schemaValidRejected == knownSchemaValidRejected, "\(counters.schemaValidRejected) valid schemas rejected (\(report))")
        #expect(counters.schemaInvalidAccepted == knownSchemaInvalidAccepted, "\(counters.schemaInvalidAccepted) invalid schemas accepted (\(report))")
        #expect(counters.instanceValidRejected == knownInstanceValidRejected, "\(counters.instanceValidRejected) valid instances rejected (\(report))")
        #expect(counters.instanceInvalidAccepted == knownInstanceInvalidAccepted, "\(counters.instanceInvalidAccepted) invalid instances accepted (\(report))")
    }

    private struct Counters {
        var groups = 0
        var schemaAgreed = 0
        var schemaValidRejected = 0
        var schemaInvalidAccepted = 0
        var instanceAgreed = 0
        var instanceValidRejected = 0
        var instanceInvalidAccepted = 0
        var failures: [String] = []

        mutating func note(_ failure: String) {
            failures.append(failure)
        }
    }

    private func runGroup(_ group: PureXML.Model.Element, directory: String, into counters: inout Counters) {
        counters.groups += 1
        let name = attribute("name", of: group) ?? "?"
        if ProcessInfo.processInfo.environment["XSTS_TRACE"] != nil {
            FileHandle.standardError.write(Data("group: \(name)\n".utf8))
        }
        guard let (schema, expectedValid) = runSchemaTests(group, name: name, directory: directory, into: &counters),
              expectedValid, let compiled = schema
        else { return }
        runInstanceTests(group, name: name, directory: directory, schema: compiled, into: &counters)
    }

    /// Compiles the group's schema tests, recording disagreements; returns
    /// the last compiled schema and whether it was expected valid.
    private func runSchemaTests(
        _ group: PureXML.Model.Element,
        name: String,
        directory: String,
        into counters: inout Counters,
    ) -> (PureXML.Schema.Document?, Bool)? {
        var schema: PureXML.Schema.Document?
        var schemaExpectedValid = true
        for schemaTest in elements(named: "schemaTest", under: .element(group)) {
            guard isAccepted(schemaTest) else { continue }
            let hrefs = references(in: .element(schemaTest), named: "schemaDocument")
            guard !hrefs.isEmpty else { continue }
            schemaExpectedValid = expectedValidity(schemaTest) != "invalid"
            let compiled = compileSchemaDocuments(hrefs, directory: directory, name: name, into: &counters)
            switch (schemaExpectedValid, compiled == nil) {
            case (true, true):
                counters.schemaValidRejected += 1
                counters.note("\(name): valid schema rejected")
            case (false, false):
                counters.schemaInvalidAccepted += 1
                counters.note("\(name): invalid schema accepted")
            default:
                counters.schemaAgreed += 1
            }
            schema = compiled
        }
        return (schema, schemaExpectedValid)
    }

    /// Compiles a schemaTest's documents into one schema. When one document
    /// imports another listed document they form an import chain and are compiled
    /// as a union so cross-document substitution groups resolve (#161); otherwise
    /// they are independent roots, composed through the lenient per-document merge
    /// (a union of independent roots wrongly trips cross-document checks).
    private func compileSchemaDocuments(
        _ hrefs: [String],
        directory: String,
        name: String,
        into counters: inout Counters,
    ) -> PureXML.Schema.Document? {
        let schemaDirectory = self.directory(of: resolve(hrefs[0], against: directory))
        let loader: (String) -> String? = { location in
            (try? String(contentsOfFile: resolve(location, against: schemaDirectory), encoding: .utf8))
        }
        let basenames = hrefs.map { String($0.split(separator: "/").last ?? "") }
        var sources: [(name: String, text: String)] = []
        for (index, href) in hrefs.enumerated() {
            guard let source = try? String(contentsOfFile: resolve(href, against: directory), encoding: .utf8) else {
                counters.note("\(name): unreadable schema \(href)")
                return nil
            }
            sources.append((basenames[index], source))
        }
        let isImportChain = sources.contains { source in
            importedBasenames(of: source.text).contains { $0 != source.name && basenames.contains($0) }
        }
        if isImportChain {
            return try? PureXML.Schema.Document(composing: sources.map(\.text), schemaLoader: loader)
        }
        var merged: PureXML.Schema.Document?
        for source in sources {
            guard let document = try? PureXML.Schema.Document(source.text, schemaLoader: loader) else { return nil }
            merged = merged.map { $0.merged(with: document) } ?? document
        }
        return merged
    }

    /// The basenames a schema source imports, includes, or redefines, used to tell
    /// an import chain (compile as a union) from independent roots (merge). Matches
    /// the `schemaLocation` attribute, not a raw substring, so a name appearing in
    /// documentation or as a suffix of another name does not misclassify.
    private func importedBasenames(of source: String) -> Set<String> {
        guard let node = try? PureXML.parse(source, limits: .init(allowDoctype: true)) else { return [] }
        var result: Set<String> = []
        for kind in ["import", "include", "redefine"] {
            for element in elements(named: kind, under: node) {
                guard let location = element.attributes.first(where: { $0.name.localName == "schemaLocation" })?.value else { continue }
                result.insert(String(location.split(separator: "/").last ?? ""))
            }
        }
        return result
    }

    private func runInstanceTests(
        _ group: PureXML.Model.Element,
        name: String,
        directory: String,
        schema: PureXML.Schema.Document,
        into counters: inout Counters,
    ) {
        for instanceTest in elements(named: "instanceTest", under: .element(group)) {
            guard isAccepted(instanceTest) else { continue }
            guard !Self.specDivergentInstances.contains(attribute("name", of: instanceTest) ?? "") else { continue }
            let expected = expectedValidity(instanceTest)
            guard expected == "valid" || expected == "invalid",
                  let href = references(in: .element(instanceTest), named: "instanceDocument").first
            else { continue }
            let instancePath = resolve(href, against: directory)
            guard let xml = try? String(contentsOfFile: instancePath, encoding: .utf8) else { continue }
            // Resolve the instance's xsi:schemaLocation hints relative to the
            // instance file, so a strict wildcard can find declarations in them.
            let instanceDirectory = self.directory(of: instancePath)
            let loader: (String) -> String? = { location in
                (try? String(contentsOfFile: resolve(location, against: instanceDirectory), encoding: .utf8))
            }
            let isValid = ((try? schema.validate(xml, schemaLoader: loader))?.isEmpty) ?? false
            if expected == "valid", !isValid {
                counters.instanceValidRejected += 1
                counters.note("\(name)/\(attribute("name", of: instanceTest) ?? "?"): valid instance rejected")
            } else if expected == "invalid", isValid {
                counters.instanceInvalidAccepted += 1
                counters.note("\(name)/\(attribute("name", of: instanceTest) ?? "?"): invalid instance accepted")
            } else {
                counters.instanceAgreed += 1
            }
        }
    }

    // MARK: Manifest helpers

    private func parsed(at path: String) throws -> PureXML.Model.Node {
        try PureXML.parse(String(contentsOfFile: path, encoding: .utf8), limits: .init(allowDoctype: true))
    }

    private func elements(named name: String, under node: PureXML.Model.Node) -> [PureXML.Model.Element] {
        var found: [PureXML.Model.Element] = []
        switch node {
        case let .document(children):
            for child in children {
                found += elements(named: name, under: child)
            }
        case let .element(element):
            if element.name.localName == name { found.append(element) }
            for child in element.children {
                found += elements(named: name, under: child)
            }
        default:
            break
        }
        return found
    }

    private func references(in node: PureXML.Model.Node, named name: String) -> [String] {
        elements(named: name, under: node).compactMap { element in
            element.attributes.first { $0.name.localName == "href" }?.value
        }
    }

    private func attribute(_ name: String, of element: PureXML.Model.Element) -> String? {
        element.attributes.first { $0.name.localName == name }?.value
    }

    /// Whether a schemaTest/instanceTest's expected outcome is settled. The suite
    /// marks disputed entries `<current status="queried">` (often with a W3C
    /// Bugzilla reference) where the expected validity is itself contested; those
    /// are not authoritative, so they are not counted as agreements or deviations.
    private func isAccepted(_ test: PureXML.Model.Element) -> Bool {
        guard let current = elements(named: "current", under: .element(test)).first else { return true }
        return (attribute("status", of: current) ?? "accepted") == "accepted"
    }

    private func expectedValidity(_ element: PureXML.Model.Element) -> String {
        elements(named: "expected", under: .element(element)).first
            .flatMap { attribute("validity", of: $0) } ?? "notKnown"
    }

    private func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "." }
        return String(path[..<slash])
    }

    /// Resolves an href against a base directory, folding `..` segments.
    private func resolve(_ href: String, against base: String) -> String {
        var parts = base.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for segment in href.split(separator: "/") {
            if segment == ".." {
                if !parts.isEmpty { parts.removeLast() }
            } else if segment != "." {
                parts.append(String(segment))
            }
        }
        return parts.joined(separator: "/")
    }
}
