@testable import PureXML
import Testing

/// Meta-tests for validation-rules.md exhaustive coverage: every shipped builtin
/// rule must have a fail and a near-miss succeed isolation test in
/// ``ValidationRule*Tests`` suites (update ``pairs`` when adding a rule or test).
@Suite("Validation rule registry")
struct ValidationRuleRegistryTests {
    private typealias RuleTestPair = (fail: String, succeed: String)

    /// Maps each ``BuiltinValidation/allRuleIDs`` entry to its isolation test names.
    private static let pairs: [String: RuleTestPair] = [
        "uniqueAttributes": ("test_uniqueAttributes", "test_uniqueAttributes_succeeds"),
        "dtdContentModel": ("test_contentModel", "test_dtdContentModel_succeeds"),
        "dtdRequiredAttributes": ("test_requiredAttributes", "test_dtdRequiredAttributes_succeeds"),
        "dtdFixedAttributeValues": ("test_fixedAttributeValues", "test_dtdFixedAttributeValues_succeeds"),
        "dtdEnumeratedAttributeValues": ("test_enumeratedAttributeValues", "test_dtdEnumeratedAttributeValues_succeeds"),
        "dtdTokenizedAttributeTypes": ("test_tokenizedAttributeTypes", "test_dtdTokenizedAttributeTypes_succeeds"),
        "dtdNotationAttributes": ("test_notationAttributes", "test_dtdNotationAttributes_succeeds"),
        "dtdUndeclaredElement": ("test_undeclaredElement", "test_dtdUndeclaredElement_succeeds"),
        "dtdUndeclaredAttributes": ("test_dtdUndeclaredAttributes", "test_dtdUndeclaredAttributes_succeeds"),
        "dtdDeclarationValidity": ("test_dtdDeclarationValidity", "test_dtdDeclarationValidity_succeeds"),
        "dtdRootElementType": ("test_dtdRootElementType", "test_dtdRootElementType_succeeds"),
        "dtdIdentifierIntegrity": ("test_identifierIntegrity", "test_dtdIdentifierIntegrity_succeeds"),
        "dtdStandaloneAttributes": ("test_dtdStandaloneAttributes", "test_dtdStandaloneAttributes_succeeds"),
        "dtdStandaloneElementWhitespace": ("test_dtdStandaloneElementWhitespace", "test_dtdStandaloneElementWhitespace_succeeds"),
        "dtdParseAdvisories": ("test_dtdParseAdvisories", "test_dtdParseAdvisories_succeeds"),
        "htmlVoidElementsAreEmpty": ("test_htmlVoidElementsAreEmpty", "test_htmlVoidElementsAreEmpty_succeeds"),
        "htmlRequiredParent": ("test_htmlRequiredParent", "test_htmlRequiredParent_succeeds"),
        "htmlUniqueIdentifiers": ("test_htmlUniqueIdentifiers", "test_htmlUniqueIdentifiers_succeeds"),
        "xsdContentValidity": ("test_xsdContentValidity", "test_xsdContentValidity_succeeds"),
        "xsdIdentityConstraints": ("test_xsdIdentityConstraints", "test_xsdIdentityConstraints_succeeds"),
        "xsdFinalRespected": ("test_xsdFinalRespected", "test_xsdFinalRespected_succeeds"),
        "xsdRestrictionsAreSubsets": ("test_xsdRestrictionsAreSubsets", "test_xsdRestrictionsAreSubsets_succeeds"),
        "conformanceMatchesExpected": ("test_conformanceMatchesExpected", "test_conformanceMatchesExpected_succeeds"),
        "xsdStreamingShallowValidity": ("test_xsdStreamingShallowValidity", "test_xsdStreamingShallowValidity_succeeds"),
    ]

    @Test("Every builtin rule id has a fail and succeed test registered")
    func test_allRulesPaired() {
        let ids = PureXML.Validation.BuiltinValidation.allRuleIDs
        #expect(Set(Self.pairs.keys) == Set(ids), "pairs keys must match allRuleIDs")
        #expect(ids.count == 24)
    }

    @Test("Builtin descriptions stay unique")
    func test_descriptionsUnique() {
        let all = PureXML.Validation.BuiltinValidation.allDescriptions
        #expect(all.count == Set(all).count)
        #expect(all.count == PureXML.Validation.BuiltinValidation.allRuleIDs.count)
    }
}
