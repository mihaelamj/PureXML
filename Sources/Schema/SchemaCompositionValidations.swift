extension PureXML.Validation.SchemaCompile {
    /// src-resolve: a resolved `include`/`import`/`redefine` `schemaLocation` (one the
    /// loader returned content for) must be a well-formed schema document. The
    /// failures are recorded on the context during composition; an unresolved
    /// location (the loader returned nothing) is not recorded, since resolution is
    /// the processor's choice.
    static var referencedSchemasResolveToSchemas: PureXML.Validation.Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
        compileRule("A resolved schemaLocation reference is a valid schema") { document in
            PureXML.Schema.SchemaLocatedFinding.unlocated(
                document.context.failedSchemaReferences.map {
                    "the referenced schema document '\($0)' is not a valid schema"
                },
            )
        }
    }

    /// src-redefine.5: every type inside `xs:redefine` must restrict or extend the
    /// type it redefines (same local name, in the redefining schema's own target
    /// namespace).
    static var redefinitionsDeriveFromThemselves: PureXML.Validation.Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
        compileRule("A redefined type restricts or extends itself") { document in
            PureXML.Schema.SchemaLocatedFinding.unlocated(
                PureXML.Schema.XSDParser.redefineDerivationErrors(document.containers),
            )
        }
    }

    /// src-redefine.6.1/7.2.1: a redefined group or attribute group has at most one
    /// self-reference, and a group self-reference occurs exactly once.
    static var redefineSelfReferencesAreWellFormed: PureXML.Validation.Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
        compileRule("A redefined group or attribute group has a well-formed self-reference") { document in
            PureXML.Schema.SchemaLocatedFinding.unlocated(
                PureXML.Schema.XSDParser.redefineSelfReferenceErrors(document.containers),
            )
        }
    }

    /// Facet definition validity and pattern syntax validity (XSD Part 2 4.3): a
    /// constraining facet must be applicable to and valid for its base type, and a
    /// `pattern` must compile. These are gathered during simple-type compilation
    /// (where the resolved base type is available) into the context's finding sink,
    /// then surfaced here as a named, located validation rather than reported
    /// straight to the diagnostics collector during parsing.
    static var simpleTypeFacetsAreValid: PureXML.Validation.Validation<PureXML.Schema.SchemaCompileRoot, PureXML.Schema.SchemaCompileContext> {
        compileRule("Simple-type facets are valid for their base type") { document in
            document.context.facetFindingSink.findings
        }
    }
}
