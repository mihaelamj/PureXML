public extension PureXML.Validation {
    /// The shipped builtin validation rules, keyed by stable description strings.
    /// Reference rules through KeyPath at `BuiltinValidation.Type` so they can be
    /// added or removed by identity (`withoutValidating`).
    enum BuiltinValidation {
        // MARK: Structural

        public static var uniqueAttributes: Validation<PureXML.Model.Element, Void> {
            Structural.uniqueAttributes
        }

        // MARK: DTD

        public static var dtdContentModel: Validation<PureXML.Model.Element, DTDSchema> {
            DTD.contentModel
        }

        public static var dtdRequiredAttributes: Validation<PureXML.Model.Element, DTDSchema> {
            DTD.requiredAttributes
        }

        public static var dtdFixedAttributeValues: Validation<PureXML.Model.Element, DTDSchema> {
            DTD.fixedAttributeValues
        }

        public static var dtdEnumeratedAttributeValues: Validation<PureXML.Model.Element, DTDSchema> {
            DTD.enumeratedAttributeValues
        }

        public static var dtdTokenizedAttributeTypes: Validation<PureXML.Model.Element, DTDSchema> {
            DTD.tokenizedAttributeTypes
        }

        public static var dtdNotationAttributes: Validation<PureXML.Model.Element, DTDSchema> {
            DTD.notationAttributes
        }

        public static var dtdUndeclaredElement: Validation<PureXML.Model.Element, DTDSchema> {
            DTD.undeclaredElement
        }

        public static var dtdUndeclaredAttributes: Validation<PureXML.Model.Element, DTDSchema> {
            DTD.undeclaredAttributes
        }

        public static var dtdDeclarationValidity: Validation<PureXML.Model.Node, DTDSchema> {
            DTD.declarationValidity
        }

        public static var dtdRootElementType: Validation<PureXML.Model.Node, DTDSchema> {
            DTD.rootElementType
        }

        public static var dtdIdentifierIntegrity: Validation<PureXML.Model.Node, DTDSchema> {
            DTD.identifierIntegrity
        }

        public static var dtdStandaloneAttributes: Validation<PureXML.Model.Element, DTDSchema> {
            DTD.standaloneAttributes
        }

        public static var dtdStandaloneElementWhitespace: Validation<PureXML.Model.Element, DTDSchema> {
            DTD.standaloneElementWhitespace
        }

        public static var dtdParseAdvisories: Validation<PureXML.Model.Node, DTDSchema> {
            DTD.parseAdvisories
        }

        // MARK: HTML

        public static var htmlVoidElementsAreEmpty: Validation<PureXML.Model.Element, Void> {
            HTML.voidElementsAreEmpty
        }

        public static var htmlRequiredParent: Validation<PureXML.Model.Element, Void> {
            HTML.requiredParent
        }

        public static var htmlUniqueIdentifiers: Validation<PureXML.Model.Node, Void> {
            HTML.uniqueIdentifiers
        }

        // MARK: XSD instance

        public static var xsdContentValidity: Validation<PureXML.Model.Node, XSDContext> {
            XSD.contentValidity
        }

        public static var xsdIdentityConstraints: Validation<PureXML.Model.Node, XSDContext> {
            XSD.identityConstraints
        }

        // MARK: XSD schema consistency

        public static var xsdFinalRespected: Validation<PureXML.Schema.SchemaTypeFact, PureXML.Schema.CompiledSchemaFacts> {
            PureXML.Validation.XSDSchema.finalRespected
        }

        public static var xsdRestrictionsAreSubsets: Validation<PureXML.Schema.SchemaTypeFact, PureXML.Schema.CompiledSchemaFacts> {
            PureXML.Validation.XSDSchema.restrictionsAreSubsets
        }

        // MARK: Conformance

        public static var conformanceMatchesExpected: Validation<ConformanceCase, Void> {
            Conformance.matchesExpected
        }

        // MARK: XSD streaming

        public static var xsdStreamingShallowValidity: Validation<PureXML.Schema.ResolvedElement, PureXML.Schema.ComplexValidator> {
            PureXML.Schema.ComplexValidator.shallowValidity
        }

        /// Stable ids for each shipped builtin rule (matches ``BuiltinValidation`` properties).
        public static let allRuleIDs: [String] = [
            "uniqueAttributes",
            "dtdContentModel",
            "dtdRequiredAttributes",
            "dtdFixedAttributeValues",
            "dtdEnumeratedAttributeValues",
            "dtdTokenizedAttributeTypes",
            "dtdNotationAttributes",
            "dtdUndeclaredElement",
            "dtdUndeclaredAttributes",
            "dtdDeclarationValidity",
            "dtdRootElementType",
            "dtdIdentifierIntegrity",
            "dtdStandaloneAttributes",
            "dtdStandaloneElementWhitespace",
            "dtdParseAdvisories",
            "htmlVoidElementsAreEmpty",
            "htmlRequiredParent",
            "htmlUniqueIdentifiers",
            "xsdContentValidity",
            "xsdIdentityConstraints",
            "xsdFinalRespected",
            "xsdRestrictionsAreSubsets",
            "conformanceMatchesExpected",
            "xsdStreamingShallowValidity",
        ]

        /// Every builtin rule description, in deterministic order, for configuration-pin tests.
        public static var allDescriptions: [String] {
            [
                uniqueAttributes.description,
                dtdContentModel.description,
                dtdRequiredAttributes.description,
                dtdFixedAttributeValues.description,
                dtdEnumeratedAttributeValues.description,
                dtdTokenizedAttributeTypes.description,
                dtdNotationAttributes.description,
                dtdUndeclaredElement.description,
                dtdUndeclaredAttributes.description,
                dtdDeclarationValidity.description,
                dtdRootElementType.description,
                dtdIdentifierIntegrity.description,
                dtdStandaloneAttributes.description,
                dtdStandaloneElementWhitespace.description,
                dtdParseAdvisories.description,
                htmlVoidElementsAreEmpty.description,
                htmlRequiredParent.description,
                htmlUniqueIdentifiers.description,
                xsdContentValidity.description,
                xsdIdentityConstraints.description,
                xsdFinalRespected.description,
                xsdRestrictionsAreSubsets.description,
                conformanceMatchesExpected.description,
                xsdStreamingShallowValidity.description,
            ]
        }
    }
}
