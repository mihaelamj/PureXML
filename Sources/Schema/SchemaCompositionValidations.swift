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
}
