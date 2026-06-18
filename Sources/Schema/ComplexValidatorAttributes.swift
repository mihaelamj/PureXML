extension PureXML.Schema.ComplexValidator {
    func validateAttributes(
        _ element: PureXML.Model.Element,
        _ type: PureXML.Schema.ComplexType,
        at path: [PureXML.Validation.PathKey],
        into errors: inout [PureXML.Validation.ValidationError],
    ) {
        let present = element.attributes.filter { !Self.isNamespaceDeclaration($0) && !Self.isSchemaInstanceAttribute($0) }
        for use in type.attributes {
            let match = present.first { Self.attributeMatches($0.name, declared: use.name, use: use, on: element.name) }
            if let match {
                if let error = use.type.validate(match.value) {
                    errors.append(PureXML.Validation.ValidationError(reason: "attribute '\(use.name.localName)': \(error)", at: path))
                }
                if let fixed = use.valueConstraint?.fixedValue, !use.type.valueMatches(match.value, literal: fixed) {
                    errors.append(PureXML.Validation.ValidationError(reason: "attribute '\(use.name.localName)' is fixed and must be '\(fixed)'", at: path))
                }
                recordIDs(use.type, value: match.value, at: path)
            } else if use.required {
                errors.append(PureXML.Validation.ValidationError(reason: "missing required attribute '\(use.name.localName)'", at: path))
            }
        }
        validateWildcardAttributes(present, element: element, type: type, at: path, into: &errors)
        if idTypedAttributeCount(present, type, on: element) > 1 {
            errors.append(PureXML.Validation.ValidationError(
                reason: "an element may carry at most one attribute of type ID",
                at: path,
            ))
        }
    }

    /// The number of `present` attributes whose effective type is `xs:ID` (an
    /// element may carry at most one; XSD 1.0 §3.4.6, cvc-complex-type). An
    /// attribute's type is its declared use's type when it matches one, otherwise
    /// the global declaration a matching wildcard admits.
    private func idTypedAttributeCount(
        _ present: [PureXML.Model.Attribute],
        _ type: PureXML.Schema.ComplexType,
        on element: PureXML.Model.Element,
    ) -> Int {
        present.reduce(into: 0) { count, attribute in
            if isIDTyped(attribute, type, on: element) { count += 1 }
        }
    }

    /// Whether `attribute`'s effective type is `xs:ID`: the type of the declared
    /// use it matches, or the global declaration a matching wildcard admits.
    private func isIDTyped(
        _ attribute: PureXML.Model.Attribute,
        _ type: PureXML.Schema.ComplexType,
        on element: PureXML.Model.Element,
    ) -> Bool {
        if let use = type.attributes.first(where: { Self.attributeMatches(attribute.name, declared: $0.name, use: $0, on: element.name) }) {
            return use.type.isID
        }
        guard let wildcard = type.attributeWildcard, wildcard.admits(attribute.name),
              let use = globalAttributeUse(for: attribute.name)
        else { return false }
        return use.type.isID
    }

    /// Whether an instance attribute satisfies a declared use. Chameleon-included
    /// global attributes may appear unprefixed on an element in the effective TN.
    static func attributeMatches(
        _ instance: PureXML.Model.QualifiedName,
        declared: PureXML.Model.QualifiedName,
        use: PureXML.Schema.AttributeUse,
        on elementName: PureXML.Model.QualifiedName,
    ) -> Bool {
        if sameName(instance, declared) { return true }
        guard use.chameleonUnprefixed,
              instance.namespaceURI == nil || instance.namespaceURI?.isEmpty == true,
              let declaredNamespace = declared.namespaceURI, !declaredNamespace.isEmpty
        else { return false }
        return instance.localName == declared.localName && declaredNamespace == elementName.namespaceURI
    }

    private func validateWildcardAttributes(
        _ present: [PureXML.Model.Attribute],
        element: PureXML.Model.Element,
        type: PureXML.Schema.ComplexType,
        at path: [PureXML.Validation.PathKey],
        into errors: inout [PureXML.Validation.ValidationError],
    ) {
        let declared = type.attributes
        let elementName = element.name
        let wildcard = type.attributeWildcard
        for attribute in present where !declared.contains(where: { Self.attributeMatches(attribute.name, declared: $0.name, use: $0, on: elementName) }) {
            guard let wildcard, wildcard.admits(attribute.name) else {
                errors.append(PureXML.Validation.ValidationError(reason: "undeclared attribute '\(attribute.name.localName)'", at: path))
                continue
            }
            switch wildcard.processContents {
            case .skip:
                continue
            case .lax:
                if let use = globalAttributeUse(for: attribute.name) {
                    validateWildcardAttribute(attribute, use: use, at: path, into: &errors)
                }
            case .strict:
                guard let use = globalAttributeUse(for: attribute.name) else {
                    errors.append(PureXML.Validation.ValidationError(
                        reason: "no declaration for wildcard-matched attribute '\(attribute.name.localName)'",
                        at: path,
                    ))
                    continue
                }
                validateWildcardAttribute(attribute, use: use, at: path, into: &errors)
            }
        }
    }

    private func globalAttributeUse(for name: PureXML.Model.QualifiedName) -> PureXML.Schema.AttributeUse? {
        globalAttributes[PureXML.Schema.XSDParser.attributeDeclarationKey(name)]
    }

    private func validateWildcardAttribute(
        _ attribute: PureXML.Model.Attribute,
        use: PureXML.Schema.AttributeUse,
        at path: [PureXML.Validation.PathKey],
        into errors: inout [PureXML.Validation.ValidationError],
    ) {
        if let error = use.type.validate(attribute.value) {
            errors.append(PureXML.Validation.ValidationError(reason: "attribute '\(attribute.name.localName)': \(error)", at: path))
        }
        if let fixed = use.valueConstraint?.fixedValue, !use.type.valueMatches(attribute.value, literal: fixed) {
            errors.append(PureXML.Validation.ValidationError(reason: "attribute '\(attribute.name.localName)' is fixed and must be '\(fixed)'", at: path))
        }
        recordIDs(use.type, value: attribute.value, at: path)
    }
}
