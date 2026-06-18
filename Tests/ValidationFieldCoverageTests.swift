import Foundation
import Testing
@testable import PureXML

/// Meta-tests for validation-rules.md full field coverage: every stored property
/// (or ``Model/Node`` case) on validation document/subject types must map to a rule
/// id in ``docs/validation-field-registry.txt`` or an explicit IGNORE entry.
@Suite("Validation field coverage")
struct ValidationFieldCoverageTests {
    private struct Registry {
        var fields: [String: [String: String]] = [:]
        var cases: [String: [String: String]] = [:]
        var ignored: [String: Set<String>] = [:]
    }

    private static let canonicalStoredProperties: [String: Set<String>] = [
        "PureXML.Validation.DTDSchema": [
            "models", "attributes", "notations", "unparsedEntities", "doctypeName",
            "parseAdvisories", "declarationErrors", "standalone", "externalElementModels", "externalAttributes", "isEmpty",
        ],
        "PureXML.Validation.XSDContext": [
            "types", "constraints", "rootDeclaration", "nillableElements", "elementConstraints",
            "abstractTypes", "typeBlock", "elementBlock", "typeDerivation",
        ],
        "PureXML.Model.Element": ["name", "attributes", "children", "text"],
        "PureXML.Model.Attribute": ["name", "value"],
        "PureXML.Validation.ConformanceCase": ["name", "actual", "expected"],
        "PureXML.Schema.SchemaTypeFact": ["name", "derivation"],
        "PureXML.Schema.CompiledSchemaFacts": ["types", "typeDerivation", "typeFinal"],
        "PureXML.Schema.ResolvedElement": ["element", "type"],
    ]

    private static let canonicalNodeCases: Set<String> = [
        "document", "element", "text", "cdata", "comment", "processingInstruction",
    ]

    private static let knownRuleTokens: Set<String> = {
        var tokens = Set(PureXML.Validation.BuiltinValidation.allRuleIDs)
        tokens.formUnion([
            "uniqueAttributes", "dtdContentModel", "dtdRequiredAttributes", "dtdFixedAttributeValues",
            "dtdEnumeratedAttributeValues", "dtdTokenizedAttributeTypes", "dtdNotationAttributes",
            "dtdUndeclaredElement", "dtdUndeclaredAttributes", "dtdDeclarationValidity",
            "dtdRootElementType", "dtdIdentifierIntegrity", "dtdStandaloneAttributes",
            "dtdStandaloneElementWhitespace", "dtdParseAdvisories", "htmlVoidElementsAreEmpty", "htmlRequiredParent",
            "htmlUniqueIdentifiers", "xsdContentValidity", "xsdIdentityConstraints",
            "xsdFinalRespected", "xsdRestrictionsAreSubsets", "conformanceMatchesExpected",
            "xsdStreamingShallowValidity",
        ])
        return tokens
    }()

    private func applyRegistryLine(_ keyword: String, parts: [String], model: inout String?, registry: inout Registry) {
        switch keyword {
        case "MODEL":
            model = parts[1]
        case "FIELD":
            guard let model else { return }
            registry.fields[model, default: [:]][parts[1]] = parts[2]
        case "CASE":
            guard let model else { return }
            registry.cases[model, default: [:]][parts[1]] = parts[2]
        case "IGNORE":
            guard let model else { return }
            registry.ignored[model, default: []].insert(parts[1])
        default:
            break
        }
    }

    private static let fixtureRelativePath = "Tests/Fixtures/validation-field-registry.txt"

    private func loadRegistry() throws -> Registry {
        let text = try Self.registryText()
        var registry = Registry()
        var currentModel: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let keyword = parts.first else { continue }
            applyRegistryLine(keyword, parts: parts, model: &currentModel, registry: &registry)
        }
        return registry
    }

    private static func registryText() throws -> String {
        #if os(WASI)
            let path = FileManager.default.currentDirectoryPath + "/" + fixtureRelativePath
            return try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        #else
            if let url = Bundle.module.url(
                forResource: "validation-field-registry",
                withExtension: "txt",
                subdirectory: "Fixtures",
            ) {
                return try String(contentsOf: url, encoding: .utf8)
            }
            let docsPath = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("docs/validation-field-registry.txt")
            return try String(contentsOf: docsPath, encoding: .utf8)
        #endif
    }

    private func ruleTokens(from listing: String) -> [String] {
        listing.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    @Test("Every stored property is classified in the field registry")
    func test_storedPropertiesCovered() throws {
        let registry = try loadRegistry()
        for (model, properties) in Self.canonicalStoredProperties {
            let covered = Set(registry.fields[model, default: [:]].keys)
            let ignored = registry.ignored[model, default: []]
            #expect(
                covered.union(ignored) == properties,
                "model \(model): missing \(properties.subtracting(covered.union(ignored)).sorted()), extra \(covered.union(ignored).subtracting(properties).sorted())",
            )
        }
    }

    @Test("Every Model.Node case is classified in the field registry")
    func test_nodeCasesCovered() throws {
        let registry = try loadRegistry()
        let covered = Set(registry.cases["PureXML.Model.Node", default: [:]].keys)
        let ignored = registry.ignored["PureXML.Model.Node", default: []]
        #expect(
            covered.union(ignored) == Self.canonicalNodeCases,
            "PureXML.Model.Node: missing \(Self.canonicalNodeCases.subtracting(covered.union(ignored)).sorted())",
        )
    }

    @Test("Registry rule tokens reference known validation rules")
    func test_ruleTokensKnown() throws {
        let registry = try loadRegistry()
        var unknown: [String] = []
        for (_, fields) in registry.fields {
            for (_, listing) in fields {
                for token in ruleTokens(from: listing) where !Self.knownRuleTokens.contains(token) {
                    unknown.append(token)
                }
            }
        }
        for (_, cases) in registry.cases {
            for (_, listing) in cases {
                for token in ruleTokens(from: listing) where !Self.knownRuleTokens.contains(token) {
                    unknown.append(token)
                }
            }
        }
        #expect(unknown.isEmpty, "unknown rule tokens: \(Set(unknown).sorted())")
    }

    @Test("A planted registry gap is detected")
    func test_plantedGapFails() throws {
        var registry = try loadRegistry()
        registry.fields["PureXML.Validation.DTDSchema", default: [:]]["__planted__"] = "dtdContentModel"
        let properties = Self.canonicalStoredProperties["PureXML.Validation.DTDSchema"] ?? []
        let covered = Set(registry.fields["PureXML.Validation.DTDSchema", default: [:]].keys)
        let ignored = registry.ignored["PureXML.Validation.DTDSchema", default: []]
        #expect(covered.union(ignored) != properties)
    }
}
