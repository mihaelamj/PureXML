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
                .validating(declarationValidity, rootElementType)
                .validating(standaloneAttributes, standaloneElementWhitespace)
            if strict { validator = validator.validating(undeclaredElement, undeclaredAttributes) }
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

        /// In strict mode, every attribute is declared (VC: Attribute Value
        /// Type). Namespace declarations are exempt: they are bindings, not
        /// attributes, in the namespace-aware model.
        static var undeclaredAttributes: Validation<DTDElement, DTDSchema> {
            .init(description: "Every attribute is declared in the DTD") { context in
                let element = context.subject
                let declarations = context.document.attributes[element.name.description] ?? []
                return element.attributes
                    .filter { attribute in
                        let name = attribute.name.description
                        guard name != "xmlns", !name.hasPrefix("xmlns:") else { return false }
                        return !declarations.contains { $0.name == name || $0.name == attribute.name.localName }
                    }
                    .map { DTDFailure(reason: "attribute '\($0.name.description)' on <\(element.name.description)> is not declared", at: context.codingPath) }
            }
        }

        /// The DTD's own declarations are valid (duplicate element types,
        /// repeated mixed names, multiple IDs, undeclared notations in lists,
        /// illegal defaults). Reported once, at the document root.
        static var declarationValidity: Validation<PureXML.Model.Node, DTDSchema> {
            .init(
                description: "The DTD declarations satisfy their validity constraints",
                check: { context in
                    context.document.declarationErrors.map { DTDFailure(reason: $0, at: context.codingPath) }
                },
                when: { $0.codingPath.isEmpty },
            )
        }

        /// The root element's type matches the DOCTYPE name (VC: Root Element
        /// Type). Reported once, at the document root.
        static var rootElementType: Validation<PureXML.Model.Node, DTDSchema> {
            .init(
                description: "The root element matches the DOCTYPE name",
                check: { context in
                    guard let expected = context.document.doctypeName,
                          case let .document(children) = context.subject,
                          let root = children.compactMap(\.element).first,
                          root.name.description != expected
                    else { return [] }
                    return [DTDFailure(reason: "root element <\(root.name.description)> does not match the DOCTYPE name '\(expected)'", at: context.codingPath)]
                },
                when: { $0.codingPath.isEmpty },
            )
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
