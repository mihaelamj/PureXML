/// The standalone validity constraints (2.9): a document declaring
/// `standalone='yes'` must not depend on markup declarations from the external
/// subset. Three dependencies are checked per element: an attribute supplied
/// by an externally-declared default, an attribute whose value changes under
/// the tokenized normalization an external declaration calls for, and
/// whitespace in element content whose model is externally declared.
extension PureXML.Validation.DTD {
    /// Externally-declared attribute defaults and normalization must not
    /// affect a standalone document.
    static var standaloneAttributes: PureXML.Validation.Validation<DTDElement, PureXML.Validation.DTDSchema> {
        .init(description: "Standalone documents do not depend on external attribute declarations") { context in
            let schema = context.document
            guard schema.standalone,
                  let declarations = schema.externalAttributes[context.subject.name.description]
            else { return [] }
            return declarations.compactMap { declaration in
                standaloneAttributeViolation(declaration, on: context.subject, at: context.codingPath)
            }
        }
    }

    /// Whitespace in element content is a dependency on the external subset
    /// when the content model is externally declared (a standalone processor
    /// could not know the whitespace is ignorable).
    static var standaloneElementWhitespace: PureXML.Validation.Validation<DTDElement, PureXML.Validation.DTDSchema> {
        .init(description: "Standalone documents have no whitespace in externally-declared element content") { context in
            let schema = context.document
            let name = context.subject.name.description
            guard schema.standalone, schema.externalElementModels.contains(name),
                  case .children = schema.models[name],
                  elementContentWhitespace(in: context.subject)
            else { return [] }
            let reason = "standalone document has whitespace in the externally-declared element content of <\(name)>"
            return [DTDFailure(reason: reason, at: context.codingPath)]
        }
    }

    private static func standaloneAttributeViolation(
        _ declaration: PureXML.Validation.AttributeDeclaration,
        on element: DTDElement,
        at path: DTDPath,
    ) -> DTDFailure? {
        let supplied = element.attributes.first {
            $0.name.description == declaration.name || $0.name.localName == declaration.name
        }
        guard let supplied else {
            // Absent attribute with an external default: the default would be
            // supplied from the external subset.
            let hasDefault = switch declaration.defaultDecl {
            case .fixed, .value: true
            case .required, .implied: false
            }
            guard hasDefault else { return nil }
            return DTDFailure(
                reason: "standalone document depends on the externally-declared default for attribute '\(declaration.name)' on <\(element.name.description)>",
                at: path,
            )
        }
        // Present attribute whose externally-declared non-CDATA type calls for
        // normalization the standalone processor would not perform.
        if case .cdata = declaration.type { return nil }
        guard supplied.value != normalize(supplied.value, for: declaration.type) else { return nil }
        return DTDFailure(
            reason: "standalone document depends on the externally-declared normalization of attribute '\(declaration.name)' on <\(element.name.description)>",
            at: path,
        )
    }

    /// Whether the element directly contains whitespace-only text.
    private static func elementContentWhitespace(in element: DTDElement) -> Bool {
        element.children.contains { child in
            if case let .text(value) = child {
                !value.isEmpty && value.allSatisfy(\.isWhitespace)
            } else {
                false
            }
        }
    }
}
