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
                .validating(contentModel)
                .validating(requiredAttributes, fixedAttributeValues, enumeratedAttributeValues)
                .validating(tokenizedAttributeTypes, notationAttributes)
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

        /// Every `#REQUIRED` attribute declared for an element is present.
        static var requiredAttributes: Validation<DTDElement, DTDSchema> {
            attributeRule("Required DTD attributes are present") { declaration, element, path in
                requiredViolation(declaration, on: element, at: path)
            }
        }

        /// Every `#FIXED` attribute, when present, holds its fixed value.
        static var fixedAttributeValues: Validation<DTDElement, DTDSchema> {
            attributeRule("#FIXED DTD attributes hold their fixed value") { declaration, element, path in
                fixedViolation(declaration, on: element, at: path)
            }
        }

        /// Every enumerated attribute, when present, holds a value from its list.
        static var enumeratedAttributeValues: Validation<DTDElement, DTDSchema> {
            attributeRule("Enumerated DTD attributes hold a listed value") { declaration, element, path in
                enumerationViolation(declaration, on: element, at: path)
            }
        }

        /// Every tokenized attribute (`NMTOKEN(S)`, `ENTITY`/`ENTITIES`), when
        /// present, matches its declared lexical form.
        static var tokenizedAttributeTypes: Validation<DTDElement, DTDSchema> {
            .init(description: "Tokenized DTD attributes match their declared type") { context in
                let element = context.subject
                let schema = context.document
                return (schema.attributes[element.name.description] ?? []).compactMap { declaration in
                    attributeValue(of: declaration, on: element).flatMap { value in
                        tokenizedTypeError(declaration, value: value, on: element.name.description, entities: schema.unparsedEntities, at: context.codingPath)
                    }
                }
            }
        }

        /// Every `NOTATION` attribute, when present, names a declared, listed
        /// notation.
        static var notationAttributes: Validation<DTDElement, DTDSchema> {
            .init(description: "NOTATION DTD attributes name a declared notation") { context in
                let element = context.subject
                let schema = context.document
                return (schema.attributes[element.name.description] ?? []).compactMap { declaration in
                    attributeValue(of: declaration, on: element).flatMap { value in
                        notationError(declaration, value: value, on: element.name.description, notations: schema.notations, at: context.codingPath)
                    }
                }
            }
        }

        /// Builds a per-declaration attribute rule: the `check` is applied to each
        /// `<!ATTLIST>` declaration for the element, gathering one failure each.
        private static func attributeRule(
            _ description: String,
            _ check: @escaping (PureXML.Validation.AttributeDeclaration, DTDElement, DTDPath) -> DTDFailure?,
        ) -> Validation<DTDElement, DTDSchema> {
            .init(description: description) { context in
                let element = context.subject
                return (context.document.attributes[element.name.description] ?? []).compactMap { check($0, element, context.codingPath) }
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
