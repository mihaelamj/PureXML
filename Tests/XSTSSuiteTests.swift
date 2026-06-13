import Foundation
@testable import PureXML
import Testing

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
    /// 2026-06-13, over 14383 groups). These ratchet down as conformance work
    /// closes deviations (#145-#148); a count rising is a regression. The
    /// instance counts reflect the #146 list-facet fix (built-in list length
    /// facets now count items). The suite is opt-in, so CI and plain
    /// `swift test` are unaffected; run it with `swift test -c release --filter
    /// XSTS` (debug is far slower and the corpus is large). Per-case deviations
    /// are written to /tmp/xsts-failures.txt for the burn-down.
    private let knownSchemaValidRejected = 75
    private let knownSchemaInvalidAccepted = 2467
    private let knownInstanceValidRejected = 547
    private let knownInstanceInvalidAccepted = 555

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
            guard let first = references(in: .element(schemaTest), named: "schemaDocument").first else { continue }
            schemaExpectedValid = expectedValidity(schemaTest) != "invalid"
            let schemaPath = resolve(first, against: directory)
            let schemaDirectory = self.directory(of: schemaPath)
            let loader: (String) -> String? = { location in
                (try? String(contentsOfFile: resolve(location, against: schemaDirectory), encoding: .utf8))
            }
            guard let source = try? String(contentsOfFile: schemaPath, encoding: .utf8) else {
                counters.note("\(name): unreadable schema \(first)")
                continue
            }
            let compiled = try? PureXML.Schema.Document(source, schemaLoader: loader)
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

    private func runInstanceTests(
        _ group: PureXML.Model.Element,
        name: String,
        directory: String,
        schema: PureXML.Schema.Document,
        into counters: inout Counters,
    ) {
        for instanceTest in elements(named: "instanceTest", under: .element(group)) {
            let expected = expectedValidity(instanceTest)
            guard expected == "valid" || expected == "invalid",
                  let href = references(in: .element(instanceTest), named: "instanceDocument").first,
                  let xml = try? String(contentsOfFile: resolve(href, against: directory), encoding: .utf8)
            else { continue }
            let isValid = ((try? schema.validate(xml))?.isEmpty) ?? false
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
