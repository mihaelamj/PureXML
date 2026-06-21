extension PureXML.Schema {
    /// The cross-cutting context for XSD schema compile-time validation rules.
    struct SchemaCompileContext {
        let schema: PureXML.Model.TreeNode
        let context: PureXML.Schema.XSDContext
        let containers: [PureXML.Model.TreeNode]
        let derivation: PureXML.Schema.XSDParser.DerivationTables?
        let globalElements: [String: PureXML.Schema.ElementType]?
        let namedTypes: [String: PureXML.Schema.ElementType]?

        init(
            schema: PureXML.Model.TreeNode,
            context: PureXML.Schema.XSDContext,
            containers: [PureXML.Model.TreeNode],
            derivation: PureXML.Schema.XSDParser.DerivationTables? = nil,
            globalElements: [String: PureXML.Schema.ElementType]? = nil,
            namedTypes: [String: PureXML.Schema.ElementType]? = nil,
        ) {
            self.schema = schema
            self.context = context
            self.containers = containers
            self.derivation = derivation
            self.globalElements = globalElements
            self.namedTypes = namedTypes
        }
    }

    /// Resolved named types and global elements produced during schema compilation.
    struct SchemaCompileNamedTypes {
        let derivation: PureXML.Schema.XSDParser.DerivationTables
        let globalElements: [String: PureXML.Schema.ElementType]
        let types: [String: PureXML.Schema.ElementType]
    }

    /// A marker subject for compile-time schema checks that run once over the
    /// whole schema document rather than per node in an instance tree.
    struct SchemaCompileRoot: PureXML.Validation.Validatable {}

    /// One schema compile finding with an optional source node for location.
    struct SchemaLocatedFinding {
        let reason: String
        let node: PureXML.Model.TreeNode?

        static func unlocated(_ reasons: [String]) -> [SchemaLocatedFinding] {
            reasons.map { SchemaLocatedFinding(reason: $0, node: nil) }
        }
    }
}

extension PureXML.Validation {
    /// XSD schema compile-time consistency, expressed as composable ``Validation``
    /// values over a ``PureXML/Schema/SchemaCompileRoot`` subject. Each rule wraps
    /// the existing compile-time check so findings stay identical while the
    /// orchestration follows the OpenAPIKit idiom.
    enum SchemaCompile {
        // MARK: Pre named-type rules

        static var idAttributesValid: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("Schema component id attributes are valid NCNames and unique") { document in
                PureXML.Schema.XSDParser.idAttributeFindings(document.schema)
            }
        }

        static var schemaStructureValid: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("Schema vocabulary elements follow the schema-for-schemas structure") { document in
                PureXML.Schema.XSDParser.structureFindings(document.schema)
            }
        }

        static var componentNamesUnique: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("Global schema component names are unique within their symbol spaces") { document in
                PureXML.Schema.SchemaLocatedFinding.unlocated(
                    PureXML.Schema.XSDParser.componentNameErrors(document.schema, document.containers, document.context),
                )
            }
        }

        static var simpleTypeFinalControlsValid: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("Simple-type final controls are declared consistently") { document in
                PureXML.Schema.XSDParser.simpleTypeFinalFindings(
                    document.schema,
                    compositionLoaded: document.context.compositionLoaded,
                    containers: document.containers,
                )
            }
        }

        static var contentModelsDeterministic: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("Schema content models are deterministic (UPA)") { document in
                PureXML.Schema.SchemaLocatedFinding.unlocated(
                    PureXML.Schema.ContentModelDeterminism.violations(in: document.schema, context: document.context),
                )
            }
        }

        static var typeDerivationAcyclic: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("Type derivation chains contain no cycles") { document in
                PureXML.Schema.XSDParser.derivationCycleFindings(
                    document.containers,
                    document.context.namespaceBindings,
                    document.context.targetNamespace,
                )
            }
        }

        static var typeReferencesAcyclic: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("Schema type references contain no cycles") { document in
                PureXML.Schema.XSDParser.circularReferenceFindings(
                    document.containers,
                    document.context.namespaceBindings,
                    document.context.targetNamespace,
                )
            }
        }

        static var allGroupReferencesPlaced: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("xs:all group references appear only where permitted") { document in
                PureXML.Schema.XSDParser.allGroupReferencePlacementFindings(
                    document.containers,
                    document.context.namespaceBindings,
                    document.context.targetNamespace,
                )
            }
        }

        static var includesCompositionValid: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("Included schemas are chameleon or match the includer targetNamespace") { document in
                PureXML.Schema.XSDParser.includeCompositionFindings(
                    document.containers,
                    mainTargetNamespace: document.context.targetNamespace,
                    compositionLoaded: document.context.compositionLoaded,
                    containerLocations: document.context.containerLocations,
                )
            }
        }

        // MARK: Post named-type rules

        static var schemaReferencesResolve: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("Every schema reference resolves to a declared component") { document in
                guard let globalElements = document.globalElements else { return [] }
                return PureXML.Schema.XSDParser.referenceFindings(
                    document.schema,
                    in: document.context,
                    elements: globalElements,
                    containers: document.containers,
                )
            }
        }

        static var attributeUsesValid: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("Attribute uses are unique and declare at most one ID attribute") { document in
                PureXML.Schema.XSDParser.attributeUseFindings(document.containers, document.context)
            }
        }

        static var idValueConstraintsValid: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("ID-typed value constraints are valid") { document in
                PureXML.Schema.XSDParser.idValueConstraintFindings(document.schema, document.context)
            }
        }

        static var substitutionMembersDeriveCorrectly: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("Substitution-group members derive correctly from their head") { document in
                guard let derivation = document.derivation, let namedTypes = document.namedTypes else { return [] }
                return PureXML.Schema.XSDParser.substitutionTypeFindings(
                    document.schema,
                    document.containers,
                    derivation,
                    namedTypes,
                    document.context,
                )
            }
        }

        static var userTypeValueConstraintsValid: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("Element value constraints are valid against their declared types") { document in
                guard let namedTypes = document.namedTypes else { return [] }
                return PureXML.Schema.XSDParser.userTypeValueConstraintFindings(document.schema, document.context, namedTypes)
                    + PureXML.Schema.XSDParser.inlineTypeValueConstraintFindings(document.schema, document.context)
            }
        }

        static var extensionAllGroupsValid: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("Complex types extending xs:all groups satisfy XSD placement rules") { document in
                guard let namedTypes = document.namedTypes else { return [] }
                return PureXML.Schema.XSDParser.extensionAllGroupFindings(document.schema, document.context, namedTypes)
            }
        }

        static var attributeRestrictionsFaithful: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("Attribute restrictions are faithful to their bases") { document in
                guard let namedTypes = document.namedTypes else { return [] }
                return PureXML.Schema.XSDParser.attributeRestrictionFindings(document.schema, document.context, namedTypes)
            }
        }

        static var simpleTypeBasesAreSimple: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("Simple types do not derive from complex types") { document in
                PureXML.Schema.XSDParser.simpleTypeBaseNotComplexFindings(document.schema, in: document.context)
            }
        }

        static var simpleTypeVarietiesValid: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("Simple-type varieties are declared consistently") { document in
                PureXML.Schema.XSDParser.simpleTypeVarietyFindings(document.schema, document.context)
            }
        }

        static var notationsValid: Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            compileRule("Notation declarations are valid") { document in
                PureXML.Schema.SchemaLocatedFinding.unlocated(
                    PureXML.Schema.XSDParser.notationValidityErrors(document.containers, document.context),
                )
            }
        }

        /// The default validator for checks that run before named types resolve.
        static func preCompileValidator() -> Validator<PureXML.Schema.SchemaCompileContext> {
            Validator<PureXML.Schema.SchemaCompileContext>.defaults(
                nonReference: [
                    AnyValidation(idAttributesValid), AnyValidation(schemaStructureValid),
                    AnyValidation(componentNamesUnique), AnyValidation(simpleTypeFinalControlsValid),
                    AnyValidation(contentModelsDeterministic), AnyValidation(attributeDeclarationsNotInXSI),
                    AnyValidation(referencedSchemasResolveToSchemas), AnyValidation(redefinitionsDeriveFromThemselves),
                    AnyValidation(redefineSelfReferencesAreWellFormed), AnyValidation(redefinedAttributeGroupsKeepRequired),
                ],
                reference: [
                    AnyValidation(typeDerivationAcyclic),
                    AnyValidation(typeReferencesAcyclic),
                    AnyValidation(allGroupReferencesPlaced),
                    AnyValidation(includesCompositionValid),
                ],
            )
        }

        /// The default validator for checks that require resolved named types.
        static func postCompileValidator() -> Validator<PureXML.Schema.SchemaCompileContext> {
            Validator<PureXML.Schema.SchemaCompileContext>.defaults(
                nonReference: [
                    AnyValidation(attributeUsesValid), AnyValidation(attributeTypesSimple),
                    AnyValidation(idValueConstraintsValid),
                    AnyValidation(userTypeValueConstraintsValid),
                    AnyValidation(extensionAllGroupsValid),
                    AnyValidation(anonymousRestrictionsValid),
                    AnyValidation(complexExtensionBaseValid), AnyValidation(redefinedGroupsRestrictBase),
                    AnyValidation(attributeRestrictionsFaithful),
                    AnyValidation(simpleTypeBasesAreSimple),
                    AnyValidation(simpleTypeVarietiesValid),
                    AnyValidation(notationsValid), AnyValidation(simpleTypeFacetsAreValid),
                ],
                reference: [
                    AnyValidation(schemaReferencesResolve),
                    AnyValidation(substitutionMembersDeriveCorrectly),
                ],
            )
        }

        /// Every pre-compile finding for a schema document.
        static func preCompileErrors(
            schema: PureXML.Model.TreeNode,
            context: PureXML.Schema.XSDContext,
            containers: [PureXML.Model.TreeNode],
        ) -> [ValidationError] {
            let document = PureXML.Schema.SchemaCompileContext(schema: schema, context: context, containers: containers)
            return preCompileValidator().errors(
                for: PureXML.Schema.SchemaCompileRoot(),
                at: [.element("schema")],
                in: document,
            )
        }

        /// Every post-compile finding for a schema document.
        static func postCompileErrors(in document: PureXML.Schema.SchemaCompileContext) -> [ValidationError] {
            postCompileValidator().errors(
                for: PureXML.Schema.SchemaCompileRoot(),
                at: [.element("schema")],
                in: document,
            )
        }

        /// Builds a post-compile context and returns every finding.
        static func postCompileErrors(
            schema: PureXML.Model.TreeNode,
            context: PureXML.Schema.XSDContext,
            containers: [PureXML.Model.TreeNode],
            namedTypes: PureXML.Schema.SchemaCompileNamedTypes,
        ) -> [ValidationError] {
            postCompileErrors(in: PureXML.Schema.SchemaCompileContext(
                schema: schema,
                context: context,
                containers: containers,
                derivation: namedTypes.derivation,
                globalElements: namedTypes.globalElements,
                namedTypes: namedTypes.types,
            ))
        }

        static func compileRule(
            _ description: String,
            _ findings: @escaping (PureXML.Schema.SchemaCompileContext) -> [PureXML.Schema.SchemaLocatedFinding],
        ) -> Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
            .init(description: description) { context in
                findings(context.document).map { finding in
                    ValidationError(
                        reason: finding.reason,
                        at: finding.node?.validationCodingPath() ?? context.codingPath,
                    )
                }
            }
        }
    }
}

extension PureXML.Validation.SchemaCompile {
    /// xsi: Not Allowed (XSD 1.0 SCC §3.2.6): no attribute declaration lands in the
    /// XSI namespace. See ``PureXML/Schema/XSDParser/xsiNamespaceAttributeFindings``.
    static var attributeDeclarationsNotInXSI: PureXML.Validation.Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
        compileRule("Attribute declarations are not in the XSI namespace") { document in
            PureXML.Schema.XSDParser.xsiNamespaceAttributeFindings(document.schema, document.context)
        }
    }

    /// au-props-correct: an attribute's type is a simple type, never complex.
    static var attributeTypesSimple: PureXML.Validation.Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
        compileRule("An attribute's type is a simple type") { document in
            guard let namedTypes = document.namedTypes else { return [] }
            return PureXML.Schema.XSDParser.attributeTypeMustBeSimpleFindings(document.schema, document.context, namedTypes)
        }
    }

    /// Particle Valid (Restriction) for anonymous (inline) complex types, which the
    /// name-keyed `restrictionsAreSubsets` rule never sees.
    static var anonymousRestrictionsValid: PureXML.Validation.Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
        compileRule("Anonymous complex-type restrictions accept a subset of their base's") { document in
            guard let namedTypes = document.namedTypes else { return [] }
            return PureXML.Schema.XSDParser.anonymousRestrictionFindings(
                document.schema,
                document.context,
                namedTypes,
                document.derivation?.typeDerivation ?? [:],
            )
        }
    }

    /// cos-ct-extends.1.4.2.2: a complexContent extension adding element content
    /// must have a base with complex (or empty) content, not simpleContent.
    static var complexExtensionBaseValid: PureXML.Validation.Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
        compileRule("A content-model derivation is consistent with its base type") { document in
            guard let namedTypes = document.namedTypes else { return [] }
            return PureXML.Schema.XSDParser.simpleContentExtensionBaseFindings(document.schema, document.context, namedTypes)
                + PureXML.Schema.XSDParser.extensionMixedAgreementFindings(document.schema, document.context, namedTypes)
                + PureXML.Schema.XSDParser.simpleContentRestrictionBaseFindings(document.schema, document.context, namedTypes)
                + PureXML.Schema.XSDParser.simpleContentRestrictionTypeFindings(document.schema, document.context, namedTypes)
                + PureXML.Schema.XSDParser.complexContentBaseKindFindings(document.schema, document.context, namedTypes)
                + PureXML.Schema.XSDParser.simpleContentExtensionBaseKindFindings(document.schema, document.context, namedTypes)
                + PureXML.Schema.XSDParser.elementValueConstraintContentFindings(document.schema, document.context, namedTypes)
        }
    }
}
