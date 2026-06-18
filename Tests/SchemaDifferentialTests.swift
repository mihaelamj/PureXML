import Foundation
import Testing
@testable import PureXML

private struct CuratedSchema {
    let label: String
    let source: String
}

@Suite("Schema differential (opt-in via SCHEMA_DIFF_ORACLE)")
struct SchemaDifferentialTests {
    private var enabled: Bool {
        ProcessInfo.processInfo.environment["SCHEMA_DIFF_ORACLE"] != nil
    }

    private var xmllint: String? {
        if let path = ProcessInfo.processInfo.environment["XMLLINT"], !path.isEmpty {
            return FileManager.default.isExecutableFile(atPath: path) ? path : nil
        }
        let defaultPath = "/usr/bin/xmllint"
        return FileManager.default.isExecutableFile(atPath: defaultPath) ? defaultPath : nil
    }

    private var xstsRoot: String? {
        ProcessInfo.processInfo.environment["XSTS_ROOT"]
    }

    private let curated: [CuratedSchema] = [
        CuratedSchema(
            label: "valid-simple",
            source: """
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
              <xs:element name="root" type="xs:string"/>
            </xs:schema>
            """,
        ),
        CuratedSchema(
            label: "invalid-duplicate-attribute",
            source: """
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
              <xs:element name="root" type="xs:string" type="xs:int"/>
            </xs:schema>
            """,
        ),
        CuratedSchema(
            label: "invalid-duplicate-global-element",
            source: """
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
              <xs:element name="a" type="xs:string"/>
              <xs:element name="a" type="xs:int"/>
            </xs:schema>
            """,
        ),
        CuratedSchema(
            label: "invalid-simpleType-two-derivations",
            source: """
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
              <xs:simpleType name="T">
                <xs:restriction base="xs:string"/>
                <xs:union memberTypes="xs:int"/>
              </xs:simpleType>
            </xs:schema>
            """,
        ),
    ]

    private let knownFuzzDisagreements: Set<UInt64> = []

    private let knownXSTSDisagreements = SchemaDifferentialXSTS.loadKnownDisagreements()

    @Test("Curated schemas agree with libxml2 on compile verdict")
    func test_curatedCorpus() throws {
        guard enabled, let xmllint else { return }
        var disagreements: [String] = []
        for item in curated {
            let pure = SchemaDifferential.pureXMLVerdict(source: item.source)
            let oracle = try compareInMemory(source: item.source, label: item.label, pure: pure, xmllint: xmllint)
            if pure != oracle {
                disagreements.append("\(item.label): purexml=\(pure) libxml2=\(oracle)")
            }
        }
        try writeReport(disagreements)
        #expect(disagreements.isEmpty)
    }

    @Test("Generative fuzz schemas: libxml2 verdict baseline")
    func test_fuzzCorpus() throws {
        guard enabled, let xmllint else { return }
        var disagreements: [String] = []
        for seed in UInt64(1) ... 32 {
            var generator = SchemaFuzzSeedGenerator(seed: seed)
            let source = generator.schema()
            let pure = SchemaDifferential.pureXMLVerdict(source: source)
            let oracle = try compareInMemory(source: source, label: "fuzz-\(seed)", pure: pure, xmllint: xmllint)
            if pure != oracle {
                disagreements.append("fuzz-\(seed)")
            }
        }
        try writeReport(disagreements.map { "\($0): verdict mismatch" })
        let unexpected = Set(disagreements.compactMap { line -> UInt64? in
            guard line.hasPrefix("fuzz-"), let value = UInt64(line.dropFirst(5)) else { return nil }
            return value
        }).subtracting(knownFuzzDisagreements)
        #expect(unexpected.isEmpty)
    }

    @Test("XSTS schema documents agree with libxml2 on compile verdict")
    func test_xstsSchemaDocuments() throws {
        guard enabled, let xmllint, let root = xstsRoot else { return }
        var disagreements: [String] = []
        let suite = try SchemaDifferentialXSTS.parsedManifest(at: root + "/suite.xml")
        for setHref in SchemaDifferentialXSTS.manifestReferences(in: suite, named: "testSetRef") {
            let setPath = root + "/" + setHref
            let setDirectory = SchemaDifferentialXSTS.directory(of: setPath)
            guard let testSet = try? SchemaDifferentialXSTS.parsedManifest(at: setPath) else { continue }
            for group in SchemaDifferentialXSTS.manifestElements(named: "testGroup", under: testSet) {
                let groupName = SchemaDifferentialXSTS.manifestAttribute("name", of: group) ?? "?"
                for schemaTest in SchemaDifferentialXSTS.manifestElements(named: "schemaTest", under: .element(group)) {
                    guard SchemaDifferentialXSTS.schemaTestAccepted(schemaTest) else { continue }
                    guard let href = SchemaDifferentialXSTS.manifestReferences(in: .element(schemaTest), named: "schemaDocument").first else {
                        continue
                    }
                    let schemaPath = SchemaDifferentialXSTS.resolve(href, against: setDirectory)
                    let schemaDirectory = SchemaDifferentialXSTS.directory(of: schemaPath)
                    let loader: (String) -> String? = { location in
                        try? String(contentsOfFile: SchemaDifferentialXSTS.resolve(location, against: schemaDirectory), encoding: .utf8)
                    }
                    guard let source = try? String(contentsOfFile: schemaPath, encoding: .utf8) else { continue }
                    let key = "\(groupName):\(href)"
                    let pure = SchemaDifferential.pureXMLVerdict(source: source, loader: loader)
                    guard let oracle = SchemaDifferential.libxml2Verdict(
                        schemaPath: schemaPath,
                        xmllint: xmllint,
                        rootElement: SchemaDifferential.rootElementName(in: source),
                    ) else { continue }
                    if pure != oracle {
                        disagreements.append(key)
                    }
                }
            }
        }
        try writeReport(disagreements.map { "\($0): verdict mismatch" })
        let unexpected = Set(disagreements).subtracting(knownXSTSDisagreements)
        #expect(unexpected.isEmpty)
    }

    private func compareInMemory(
        source: String,
        label: String,
        pure: SchemaCompileVerdict,
        xmllint: String,
    ) throws -> SchemaCompileVerdict {
        let directory = NSTemporaryDirectory() + "purexml-schema-diff-\(label)-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let schemaPath = directory + "/schema.xsd"
        try source.write(toFile: schemaPath, atomically: true, encoding: .utf8)
        guard let oracle = SchemaDifferential.libxml2Verdict(
            schemaPath: schemaPath,
            xmllint: xmllint,
            rootElement: SchemaDifferential.rootElementName(in: source),
        ) else {
            return pure
        }
        return oracle
    }

    private func writeReport(_ lines: [String]) throws {
        guard !lines.isEmpty else { return }
        let body = lines.joined(separator: "\n") + "\n"
        try body.write(toFile: "/tmp/schema-differential.txt", atomically: true, encoding: .utf8)
    }
}
