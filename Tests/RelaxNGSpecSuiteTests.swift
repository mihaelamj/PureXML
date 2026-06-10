import Foundation
@testable import PureXML
import Testing

/// Opt-in runner for James Clark's RELAX NG spec test suite (`spectest.xml`,
/// distributed with jing-trang under its BSD license). Point `RNG_TS_ROOT` at
/// the directory containing `spectest.xml` to run; without the variable the
/// suite is skipped and it is never vendored into this repository. The
/// manifest nests testSuite/testCase elements: an `incorrect` schema must
/// fail to compile, a `correct` schema must compile and then `valid`
/// instances validate while `invalid` instances do not. `resource` and `dir`
/// elements model the include/externalRef files a case references, served to
/// the compiler through its loader keyed by relative path. Foundation is used
/// for file access only.
@Suite("RELAX NG spec suite (opt-in via RNG_TS_ROOT)")
struct RelaxNGSpecSuiteTests {
    private var root: String? {
        ProcessInfo.processInfo.environment["RNG_TS_ROOT"]
    }

    /// The burn-down frontier, by case index in document order (exact, so
    /// progress and regressions both show). Three classes:
    /// 1. Schema correctness is not validated: every `incorrect` schema
    ///    compiles (the count is asserted exactly below). Closing it means
    ///    validating schemas against the RELAX NG grammar and the section
    ///    4.16-4.18 restrictions before pattern interpretation.
    /// 2. Simplification gaps reject valid instances: foreign-namespace
    ///    element/attribute stripping (4.1: cases 90-98), xml:base-aware
    ///    include/externalRef resolution (4.5: 100-101), include/div/override
    ///    depth (4.6-4.12), the 4.17-4.18 normalization corners, and the
    ///    section 6 compatibility datatypes (ID/IDREF, 6.2.x).
    /// 3. The same classes accept some `invalid` instances.
    private let knownIncorrectCompiledCount = 213
    private let knownCorrectRejected: Set<Int> = []
    private let knownValidRejected: Set<Int> = [
        98, 104, 109, 110, 111, 115, 119, 120, 124, 125, 126, 127, 128, 130,
        131, 132, 133, 142, 190, 191, 194, 195, 208, 209, 210, 236, 256, 258,
        265, 266, 268, 269, 271, 328, 372, 374, 378, 379, 380,
    ]
    private let knownInvalidAccepted: Set<Int> = [
        104, 124, 125, 126, 127, 128, 142, 264, 271,
    ]

    private struct SpecCase {
        let index: Int
        let section: String
        let schema: String
        let mustCompile: Bool
        let validInstances: [String]
        let invalidInstances: [String]
        let resources: [String: String]
    }

    private final class Collector {
        var cases: [SpecCase] = []
        var counter = 0
    }

    private func loadCases(from path: String) throws -> [SpecCase] {
        let source = try String(contentsOfFile: path, encoding: .utf8)
        let document = try PureXML.parse(source, limits: .init(allowDoctype: true))
        guard case let .document(children) = document,
              let suite = children.compactMap(\.element).first
        else { return [] }
        let collector = Collector()
        collect(suite, resources: [:], collector: collector)
        return collector.cases
    }

    /// Walks nested testSuite elements, accumulating the `resource`/`dir`
    /// definitions in scope, and turns each testCase into a SpecCase.
    private func collect(_ element: PureXML.Model.Element, resources: [String: String], collector: Collector) {
        var scope = resources
        for child in element.children.compactMap(\.element) {
            switch child.name.localName {
            case "resource", "dir":
                merge(child, prefix: "", into: &scope)
            default:
                break
            }
        }
        for child in element.children.compactMap(\.element) {
            switch child.name.localName {
            case "testSuite":
                collect(child, resources: scope, collector: collector)
            case "testCase":
                appendCase(child, resources: scope, collector: collector)
            default:
                break
            }
        }
    }

    /// Files a `resource` (name -> serialized content) or recurses into a
    /// `dir`, prefixing names with the directory path.
    private func merge(_ element: PureXML.Model.Element, prefix: String, into scope: inout [String: String]) {
        let name = element.attributes.first { $0.name.description == "name" }?.value ?? ""
        if element.name.localName == "resource" {
            if let content = firstElementChild(element) {
                scope[prefix + name] = PureXML.serialize(.element(content))
            }
            return
        }
        for child in element.children.compactMap(\.element) {
            merge(child, prefix: prefix + name + "/", into: &scope)
        }
    }

    private func firstElementChild(_ element: PureXML.Model.Element) -> PureXML.Model.Element? {
        element.children.compactMap(\.element).first
    }

    /// The wrapper's first element child, serialized back to markup.
    private func serializedChild(_ element: PureXML.Model.Element) -> String? {
        firstElementChild(element).map { PureXML.serialize(.element($0)) }
    }

    private func appendCase(_ testCase: PureXML.Model.Element, resources: [String: String], collector: Collector) {
        var scope = resources
        var section = ""
        var schema: String?
        var mustCompile = true
        var valid: [String] = []
        var invalid: [String] = []
        for child in testCase.children.compactMap(\.element) {
            switch child.name.localName {
            case "section":
                section = child.children.compactMap { if case let .text(value) = $0 { value } else { nil } }.joined()
            case "resource", "dir":
                merge(child, prefix: "", into: &scope)
            case "correct", "incorrect":
                mustCompile = child.name.localName == "correct"
                schema = serializedChild(child)
            case "valid":
                serializedChild(child).map { valid.append($0) }
            case "invalid":
                serializedChild(child).map { invalid.append($0) }
            default:
                break
            }
        }
        guard let schema else { return }
        collector.counter += 1
        collector.cases.append(SpecCase(
            index: collector.counter,
            section: section,
            schema: schema,
            mustCompile: mustCompile,
            validInstances: valid,
            invalidInstances: invalid,
            resources: scope,
        ))
    }

    @Test("Every spec case behaves: compile, reject, validate, invalidate")
    func test_specSuite() throws {
        guard let root else {
            return // Opt-in: suite not present.
        }
        let cases = try loadCases(from: root + "/spectest.xml")
        var incorrectAccepted: [Int] = []
        var correctRejected: [String: String] = [:]
        var validRejected: [String] = []
        var invalidAccepted: [String] = []
        for specCase in cases {
            let resources = specCase.resources
            let loader: (String) -> String? = { resources[$0] }
            let compiled = try? PureXML.Schema.RelaxNG(specCase.schema, schemaLoader: loader)
            guard specCase.mustCompile else {
                if compiled != nil {
                    incorrectAccepted.append(specCase.index)
                }
                continue
            }
            guard let compiled else {
                if !knownCorrectRejected.contains(specCase.index) {
                    correctRejected["#\(specCase.index) §\(specCase.section)"] = compileError(specCase, loader: loader)
                }
                continue
            }
            for (offset, instance) in specCase.validInstances.enumerated() {
                let accepted = (try? compiled.validate(instance)) == true
                if !accepted, !knownValidRejected.contains(specCase.index) {
                    validRejected.append("#\(specCase.index).\(offset) §\(specCase.section)")
                }
            }
            for (offset, instance) in specCase.invalidInstances.enumerated() {
                let accepted = (try? compiled.validate(instance)) == true
                if accepted, !knownInvalidAccepted.contains(specCase.index) {
                    invalidAccepted.append("#\(specCase.index).\(offset) §\(specCase.section)")
                }
            }
        }
        #expect(
            incorrectAccepted.count == knownIncorrectCompiledCount,
            "incorrect-schema class drifted: \(incorrectAccepted.count) (baseline \(knownIncorrectCompiledCount))",
        )
        #expect(correctRejected.isEmpty, "rejected \(correctRejected.count) correct schemas: \(correctRejected)")
        #expect(validRejected.isEmpty, "rejected \(validRejected.count) valid instances: \(validRejected)")
        #expect(invalidAccepted.isEmpty, "accepted \(invalidAccepted.count) invalid instances: \(invalidAccepted)")
    }

    private func compileError(_ specCase: SpecCase, loader: @escaping (String) -> String?) -> String {
        do {
            _ = try PureXML.Schema.RelaxNG(specCase.schema, schemaLoader: loader)
            return "compiled on retry"
        } catch {
            return String(describing: error)
        }
    }
}
