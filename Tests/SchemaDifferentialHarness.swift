import Foundation
@testable import PureXML

/// Whether PureXML accepts or rejects compiling a schema document.
enum SchemaCompileVerdict: Equatable, Sendable {
    case accepts
    case rejects
}

/// Opt-in differential harness (#171): compare PureXML's schema compile verdict
/// to libxml2's `xmllint --schema` (schema compilation phase).
enum SchemaDifferential {
    static func pureXMLVerdict(source: String, loader: @escaping (String) -> String? = { _ in nil }) -> SchemaCompileVerdict {
        (try? PureXML.Schema.Document(source, schemaLoader: loader)) == nil ? .rejects : .accepts
    }

    static func rootElementName(in source: String) -> String? {
        guard let root = try? PureXML.parseTree(source),
              let schema = root.elementChildren.first(where: {
                  $0.name?.localName == "schema" && $0.name?.namespaceURI == "http://www.w3.org/2001/XMLSchema"
              })
        else { return "root" }
        for child in schema.elementChildren {
            guard child.name?.localName == "element",
                  child.name?.namespaceURI == "http://www.w3.org/2001/XMLSchema",
                  child.attributes.first(where: { $0.name.localName == "ref" }) == nil,
                  let name = child.attributes.first(where: { $0.name.localName == "name" })?.value
            else { continue }
            return name
        }
        return "root"
    }

    static func libxml2Verdict(
        schemaPath: String,
        xmllint: String,
        rootElement: String? = nil,
    ) -> SchemaCompileVerdict? {
        #if os(WASI)
            return nil
        #else
            let directory = (schemaPath as NSString).deletingLastPathComponent
            let fileName = (schemaPath as NSString).lastPathComponent
            let instanceName = ".purexml-schema-diff-instance.xml"
            let instancePath = directory + "/" + instanceName
            let element = rootElement ?? "root"
            let instance = "<\(element)/>"
            do {
                try instance.write(toFile: instancePath, atomically: true, encoding: .utf8)
                defer { try? FileManager.default.removeItem(atPath: instancePath) }
                let process = Process()
                process.executableURL = URL(fileURLWithPath: xmllint)
                process.arguments = ["--noout", "--schema", fileName, instanceName]
                process.currentDirectoryURL = URL(fileURLWithPath: directory.isEmpty ? "." : directory)
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self)
                return libxml2CompiledSchema(output: output, exitCode: process.terminationStatus, schemaFile: fileName)
                    ? .accepts
                    : .rejects
            } catch {
                return nil
            }
        #endif
    }

    private static func libxml2CompiledSchema(output: String, exitCode: Int32, schemaFile: String) -> Bool {
        if output.contains("WXS schema \(schemaFile) failed to compile") { return false }
        if output.contains("Schemas parser error"), output.contains(schemaFile) { return false }
        if output.contains("Failed to parse the XML resource '\(schemaFile)'") { return false }
        if exitCode == 5 { return false }
        if exitCode == 1, output.localizedCaseInsensitiveContains("parser error"), output.contains(schemaFile) {
            return false
        }
        return true
    }
}

enum SchemaDifferentialXSTS {
    static func loadKnownDisagreements() -> Set<String> {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/schema-differential-xsts-baseline.txt")
        guard let text = try? String(contentsOf: path, encoding: .utf8) else { return [] }
        return Set(text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty })
    }

    static func parsedManifest(at path: String) throws -> PureXML.Model.Node {
        try PureXML.parse(String(contentsOfFile: path, encoding: .utf8), limits: .init(allowDoctype: true))
    }

    static func manifestElements(named name: String, under node: PureXML.Model.Node) -> [PureXML.Model.Element] {
        var found: [PureXML.Model.Element] = []
        switch node {
        case let .document(children):
            for child in children {
                found += manifestElements(named: name, under: child)
            }
        case let .element(element):
            if element.name.localName == name { found.append(element) }
            for child in element.children {
                found += manifestElements(named: name, under: child)
            }
        default:
            break
        }
        return found
    }

    static func manifestReferences(in node: PureXML.Model.Node, named name: String) -> [String] {
        manifestElements(named: name, under: node).compactMap { element in
            element.attributes.first { $0.name.localName == "href" }?.value
        }
    }

    static func manifestAttribute(_ name: String, of element: PureXML.Model.Element) -> String? {
        element.attributes.first { $0.name.localName == name }?.value
    }

    static func schemaTestAccepted(_ test: PureXML.Model.Element) -> Bool {
        guard let current = manifestElements(named: "current", under: .element(test)).first else { return true }
        return (manifestAttribute("status", of: current) ?? "accepted") == "accepted"
    }

    static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "." }
        return String(path[..<slash])
    }

    static func resolve(_ href: String, against base: String) -> String {
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

struct SchemaFuzzSeedGenerator {
    private var rng: DifferentialSeededRNG

    init(seed: UInt64) {
        rng = DifferentialSeededRNG(seed: seed == 0 ? 1 : seed)
    }

    private static let leafTypes = ["xs:string", "xs:int", "xs:boolean"]

    private mutating func pick<T>(_ options: [T]) -> T {
        options[Int.random(in: 0 ..< options.count, using: &rng)]
    }

    private mutating func toss() -> Bool {
        Bool.random(using: &rng)
    }

    mutating func schema() -> String {
        """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"\
        \(toss() ? " targetNamespace=\"urn:t\"" : "")>
          <xs:element name="root" type="\(pick(Self.leafTypes))"/>
        </xs:schema>
        """
    }
}

private struct DifferentialSeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 0x2545_F491_4F6C_DD1D
    }
}
