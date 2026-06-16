import Foundation
@testable import PureXML
import Testing

/// Opt-in diagnostics for XSTS valid-instance rejections. Set `XSTS_ROOT` and
/// `XSTS_DIAG=1` to print validation errors for every remaining #146 failure.
@Suite("XSTS diagnostics (opt-in via XSTS_ROOT and XSTS_DIAG)")
struct SchemaXSTSDiagnosticTests {
    private var root: String? {
        ProcessInfo.processInfo.environment["XSTS_ROOT"]
    }

    @Test("Print errors for remaining valid-instance rejections")
    func test_printFailures() throws {
        guard ProcessInfo.processInfo.environment["XSTS_DIAG"] != nil, let root else { return }
        let failures = try String(contentsOfFile: "/tmp/xsts-failures.txt", encoding: .utf8)
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard line.contains("valid instance rejected") else { return nil }
                return String(line.split(separator: ":")[0])
            }
        let suite = try PureXML.parse(String(contentsOfFile: root + "/suite.xml", encoding: .utf8), limits: .init(allowDoctype: true))
        for sample in failures {
            let errors = try runSample(sample, root: root, suite: suite)
            if !errors.isEmpty {
                print("\(sample): \(errors.map(\.description).joined(separator: " | "))")
            }
        }
    }

    private func runSample(_ sample: String, root: String, suite: PureXML.Model.Node) throws -> [PureXML.Validation.ValidationError] {
        let parts = sample.split(separator: "/", maxSplits: 1)
        guard parts.count == 2,
              let (group, dir) = findGroup(named: String(parts[0]), root: root, suite: suite)
        else { return [] }
        var schema: PureXML.Schema.Document?
        for schemaTest in elements(named: "schemaTest", under: .element(group)) {
            for href in references(in: schemaTest, named: "schemaDocument") {
                let schemaPath = resolve(href, against: dir)
                let schemaDirectory = directory(of: schemaPath)
                let loader: (String) -> String? = { (try? String(contentsOfFile: resolve($0, against: schemaDirectory), encoding: .utf8)) }
                guard let source = try? String(contentsOfFile: schemaPath, encoding: .utf8),
                      let compiled = try? PureXML.Schema.Document(source, schemaLoader: loader)
                else { continue }
                schema = schema.map { $0.merged(with: compiled) } ?? compiled
            }
        }
        guard let schema else { return [] }
        for instanceTest in elements(named: "instanceTest", under: .element(group)) {
            guard attribute("name", of: instanceTest) == String(parts[1]) else { continue }
            guard let href = references(in: instanceTest, named: "instanceDocument").first else { continue }
            let instancePath = resolve(href, against: dir)
            guard let xml = try? String(contentsOfFile: instancePath, encoding: .utf8) else { continue }
            let instanceDirectory = directory(of: instancePath)
            let loader: (String) -> String? = { (try? String(contentsOfFile: resolve($0, against: instanceDirectory), encoding: .utf8)) }
            return (try? schema.validate(xml, schemaLoader: loader)) ?? []
        }
        return []
    }

    private func findGroup(named name: String, root: String, suite: PureXML.Model.Node) -> (PureXML.Model.Element, String)? {
        guard case let .document(suiteChildren) = suite else { return nil }
        for child in suiteChildren {
            guard case let .element(suiteElement) = child else { continue }
            for setHref in references(in: suiteElement, named: "testSetRef") {
                let setPath = root + "/" + setHref
                let setDirectory = directory(of: setPath)
                guard let setText = try? String(contentsOfFile: setPath, encoding: .utf8),
                      let setNode = try? PureXML.parse(setText, limits: .init(allowDoctype: true))
                else { continue }
                for group in elements(named: "testGroup", under: setNode) where attribute("name", of: group) == name {
                    return (group, setDirectory)
                }
            }
        }
        return nil
    }

    private func elements(named name: String, under node: PureXML.Model.Node) -> [PureXML.Model.Element] {
        var found: [PureXML.Model.Element] = []
        switch node {
        case let .document(children): for child in children {
                found += elements(named: name, under: child)
            }
        case let .element(element):
            if element.name.localName == name { found.append(element) }
            for child in element.children {
                found += elements(named: name, under: child)
            }
        default: break
        }
        return found
    }

    private func references(in element: PureXML.Model.Element, named name: String) -> [String] {
        elements(named: name, under: .element(element)).compactMap {
            $0.attributes.first { $0.name.localName == "href" }?.value
        }
    }

    private func attribute(_ name: String, of element: PureXML.Model.Element) -> String? {
        element.attributes.first { $0.name.localName == name }?.value
    }

    private func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "." }
        return String(path[..<slash])
    }

    private func resolve(_ href: String, against base: String) -> String {
        var parts = base.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for segment in href.split(separator: "/") {
            if segment == ".." { if !parts.isEmpty { parts.removeLast() } } else if segment != "." { parts.append(String(segment)) }
        }
        return parts.joined(separator: "/")
    }
}
