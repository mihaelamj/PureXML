/// File-scope aliases for the DTD validation rules and helpers, kept out of the
/// `DTD` enum to avoid nesting a type two levels deep.
typealias DTDElement = PureXML.Model.Element
typealias DTDPath = [PureXML.Validation.PathKey]
typealias DTDFailure = PureXML.Validation.ValidationError

public extension PureXML.Validation {
    /// DTD validation as composable rules over a ``DTDSchema`` document: every
    /// element is checked against its content model and attribute declarations,
    /// and ID/IDREF integrity is checked once over the whole tree. Replaces the
    /// imperative walk with declared ``Validation`` values.
    enum DTD {
        /// A validator for a ``DTDSchema``. In strict mode every element must also
        /// be declared.
        static func validator(strict: Bool) -> Validator<DTDSchema> {
            var validator = Validator<DTDSchema>.blank
                .validating(contentModel, attributeDeclarations)
                .validating(identifierIntegrity)
            if strict { validator = validator.validating(undeclaredElement) }
            return validator
        }

        /// Each element's content matches its `<!ELEMENT>` model.
        static var contentModel: Validation<DTDElement, DTDSchema> {
            .init(description: "Element content matches its DTD content model") { context in
                let element = context.subject
                guard let model = context.document.models[element.name.description] else { return [] }
                return contentViolations(element, model: model, at: context.codingPath)
            }
        }

        /// Each element's attributes satisfy their `<!ATTLIST>` declarations
        /// (required presence, `#FIXED` value, and enumerations).
        static var attributeDeclarations: Validation<DTDElement, DTDSchema> {
            .init(description: "Element attributes satisfy their DTD declarations") { context in
                let element = context.subject
                guard let declarations = context.document.attributes[element.name.description] else { return [] }
                return declarations.flatMap { declaration in
                    attributeViolations(declaration, on: element, at: context.codingPath)
                }
            }
        }

        /// In strict mode, every element is declared in the DTD.
        static var undeclaredElement: Validation<DTDElement, DTDSchema> {
            .init(description: "Element is declared in the DTD") { context in
                context.document.models[context.subject.name.description] != nil
            }
        }

        /// ID values are unique and every IDREF resolves. Runs once over the whole
        /// tree (a reference may point forward), so it is gated to the root.
        static var identifierIntegrity: Validation<PureXML.Model.Node, DTDSchema> {
            .init(
                description: "DTD ID values are unique and IDREFs resolve",
                check: { context in identifierErrors(context.subject, schema: context.document, at: context.codingPath) },
                when: { $0.codingPath.isEmpty },
            )
        }
    }
}
