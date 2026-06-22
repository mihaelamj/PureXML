public extension PureXML.Schema {
    /// An element paired with its already-resolved effective type: the subject of
    /// the streaming XSD content rule, so the contextual type resolution that a
    /// node-tree walk cannot express is carried on the subject instead.
    struct ResolvedElement: PureXML.Validation.Validatable {
        public let element: PureXML.Model.Element
        public let type: ElementType
        /// The matched particle's `default`/`fixed` value constraint, when the element
        /// is a content-model child, so an empty element validates that value.
        public let valueConstraint: ValueConstraint?

        public init(element: PureXML.Model.Element, type: ElementType, valueConstraint: ValueConstraint? = nil) {
            self.element = element
            self.type = type
            self.valueConstraint = valueConstraint
        }
    }
}

public extension PureXML.Schema.ComplexValidator {
    // MARK: Streaming support

    /// The streaming XSD content check as a composable ``PureXML/Validation`` value
    /// (the OpenAPIKit idiom): an element is valid against its resolved type. The
    /// validator is the document, the cross-cutting context that holds the type
    /// tables, so the streaming path is rule-driven like every other validator
    /// rather than a bare method call.
    static var shallowValidity: PureXML.Validation.Validation<PureXML.Schema.ResolvedElement, PureXML.Schema.ComplexValidator> {
        .init(description: "Each streamed element is valid against its declared XSD type") { context in
            context.document.validateShallow(
                context.subject.element,
                as: context.subject.type,
                valueConstraint: context.subject.valueConstraint,
                at: context.codingPath,
            )
        }
    }

    /// The matched particle's `default`/`fixed` value constraint for a child of
    /// `parent`'s content model, keyed by namespaced identity (so same-local-name
    /// elements in different types do not collide as in the flat `elementConstraints`).
    func childValueConstraint(of parent: PureXML.Schema.ElementType, child name: PureXML.Model.QualifiedName) -> PureXML.Schema.ValueConstraint? {
        guard case let .complex(complex) = parent else { return nil }
        switch complex.content {
        case let .elementOnly(particle), let .mixed(particle):
            return Self.elementValueConstraints(in: particle.term)[Self.key(name)]
        case .empty, .simpleContent:
            return nil
        }
    }

    /// The effective element type after an `xsi:type` override and following any
    /// `typeReference` chain, so the streaming driver resolves a type once per
    /// element rather than re-entering the tree walk. The `xsi:type` is resolved
    /// through its in-scope prefix bindings to a namespaced type key (as the tree
    /// path does), so two imported types sharing a local name do not collide.
    func effectiveType(
        _ declared: PureXML.Schema.ElementType,
        of element: PureXML.Model.Element,
        namespaceBindings: [String: String] = [:],
    ) -> PureXML.Schema.ElementType {
        var type = declared
        if let resolved = resolvedXsiType(element, namespaceBindings: namespaceBindings) {
            type = resolved
        }
        // An unknown or circular chain stays a typeReference, which
        // validateShallow reports as a located error.
        if case let .resolved(resolved) = resolveReference(type) {
            type = resolved
        }
        return type
    }

    /// The type an element's `xsi:type` resolves to through its in-scope prefix
    /// bindings, or nil when the named type is undeclared. Used by the streaming
    /// driver to report an unknown `xsi:type` the way the tree path does.
    func resolvedXsiType(_ element: PureXML.Model.Element, namespaceBindings: [String: String]) -> PureXML.Schema.ElementType? {
        guard let reference = Self.xsiTypeReference(element, namespaceBindings: namespaceBindings) ?? Self.xsiTypeName(element) else {
            return nil
        }
        return Self.resolveNamedType(reference, in: types)
    }

    /// The declared element type of a child `name` in `parent`'s content model: a
    /// named particle member, or a global declaration reached through a matching
    /// wildcard's `processContents`. Returns nil when the parent has no element
    /// content, when `processContents="skip"`, or when the child is not declared
    /// and no wildcard admits it (the parent's structure check reports that).
    func childType(of parent: PureXML.Schema.ElementType, child name: PureXML.Model.QualifiedName) -> PureXML.Schema.ElementType? {
        guard case let .complex(complex) = parent else { return nil }
        switch complex.content {
        case let .elementOnly(particle), let .mixed(particle):
            if let type = Self.elementTypes(in: particle.term)[Self.key(name)] {
                return type
            }
            return wildcardChildType(for: name, in: particle.term)
        case .empty, .simpleContent:
            return nil
        }
    }

    /// The error when a strict wildcard admits a child but no global declaration
    /// exists for it, matching the tree validator's ``validateWildcardChild``.
    func strictWildcardError(
        for child: PureXML.Model.QualifiedName,
        in parent: PureXML.Schema.ElementType,
        at path: [PureXML.Validation.PathKey],
    ) -> PureXML.Validation.ValidationError? {
        guard case let .complex(complex) = parent else { return nil }
        switch complex.content {
        case let .elementOnly(particle), let .mixed(particle):
            if Self.elementTypes(in: particle.term)[Self.key(child)] != nil { return nil }
            guard Self.wildcardMatch(for: child, in: particle.term) == .strict,
                  types[PureXML.Schema.XSDParser.elementDeclarationKey(child)] == nil
            else { return nil }
            return PureXML.Validation.ValidationError(
                reason: "no declaration for wildcard-matched element '\(child.localName)'",
                at: path,
            )
        case .empty, .simpleContent:
            return nil
        }
    }

    /// The `processContents` of a wildcard in `term` that admits `name`, if any.
    static func wildcardMatch(for name: PureXML.Model.QualifiedName, in term: PureXML.Schema.Term) -> PureXML.Schema.ProcessContents? {
        switch term {
        case let .wildcard(wildcard):
            return wildcard.admits(name) ? wildcard.processContents : nil
        case .element:
            return nil
        case let .group(group):
            for member in group.particles {
                if let match = wildcardMatch(for: name, in: member.term) { return match }
            }
            return nil
        }
    }

    private func wildcardChildType(for name: PureXML.Model.QualifiedName, in term: PureXML.Schema.Term) -> PureXML.Schema.ElementType? {
        guard let process = Self.wildcardMatch(for: name, in: term) else { return nil }
        switch process {
        case .skip:
            return nil
        case .lax, .strict:
            // Match the global declaration by full qualified name only; a global is
            // always in the target namespace, so the namespaced key already covers a
            // no-namespace global without conflating distinct namespaces.
            return types[PureXML.Schema.XSDParser.elementDeclarationKey(name)]
        }
    }

    /// Validates one element's own attributes and content-model structure (child
    /// names, order, occurrence) and simple content, but not its children's own
    /// validity, which the streaming driver checks as each child closes. `type`
    /// must already be effective (see ``effectiveType(_:of:)``).
    func validateShallow(
        _ element: PureXML.Model.Element,
        as type: PureXML.Schema.ElementType,
        valueConstraint: PureXML.Schema.ValueConstraint? = nil,
        at path: [PureXML.Validation.PathKey] = [],
    ) -> [PureXML.Validation.ValidationError] {
        var errors: [XSDFailure] = []
        switch type {
        case let .simple(simple):
            validateSimpleElement(element, simple, valueConstraint: valueConstraint, at: path, into: &errors)
        case let .complex(complex):
            validateAttributes(element, complex, at: path, into: &errors)
            if let nilErrors = nilErrors(element, at: path) { return errors + nilErrors }
            shallowContent(element, complex.content, at: path, into: &errors)
            // A simpleContent fixed value is compared in its simple type's value space
            // (cvc-elt.5.2.2.1), matching the tree path's validate(_:against:).
            let simpleContentType: PureXML.Schema.SimpleType? = if case let .simpleContent(simple) = complex.content { simple } else { nil }
            errors += elementFixedErrors(element, valueType: simpleContentType, at: path)
        case .typeReference:
            // The shared resolver also guards a circular chain, which would
            // otherwise recurse here without terminating.
            switch resolveReference(type) {
            case let .unknown(name):
                return [XSDFailure(reason: "unknown type '\(name)'", at: path)]
            case let .circular(name):
                return [XSDFailure(reason: "circular type reference '\(name)'", at: path)]
            case let .resolved(resolved):
                return validateShallow(element, as: resolved, valueConstraint: valueConstraint, at: path)
            }
        }
        return errors
    }

    private func validateSimpleElement(
        _ element: PureXML.Model.Element,
        _ simple: PureXML.Schema.SimpleType,
        valueConstraint: PureXML.Schema.ValueConstraint? = nil,
        at path: XSDPath,
        into errors: inout [XSDFailure],
    ) {
        if let nilErrors = nilErrors(element, fixedValue: valueConstraint?.fixedValue, at: path) {
            errors += nilErrors
            return
        }
        if !element.children.compactMap(\.element).isEmpty {
            errors.append(XSDFailure(reason: "'\(element.name.localName)' must not have children", at: path))
        }
        // An empty element takes its `default`/`fixed` value; that value (not the
        // empty string) is what must be valid against the type, matching the tree
        // path's validateChild.
        let text = Self.rawTextContent(element)
        if let error = simple.validate(effectiveSimpleText(for: element, particleConstraint: valueConstraint)) {
            errors.append(XSDFailure(reason: "'\(element.name.localName)': \(error)", at: path))
        }
        recordIDs(simple, value: text, at: path)
        // Compare a present fixed value in the type's value space (e.g. "05" == "5"
        // for xs:int) and against the matched particle's fixed value, as the tree
        // path's validateChild does, not a raw string compare.
        errors += elementFixedErrors(element, valueType: simple, particleFixed: valueConstraint?.fixedValue, at: path)
    }

    private func shallowContent(_ element: PureXML.Model.Element, _ content: PureXML.Schema.ContentType, at path: XSDPath, into errors: inout [XSDFailure]) {
        let children = element.children.compactMap(\.element)
        switch content {
        case .empty:
            if !children.isEmpty { errors.append(XSDFailure(reason: "element must be empty", at: path)) }
            rejectText(element, at: path, into: &errors)
        case let .simpleContent(type):
            if !children.isEmpty { errors.append(XSDFailure(reason: "element must not have children", at: path)) }
            let text = Self.rawTextContent(element)
            if let error = type.validate(text) {
                errors.append(XSDFailure(reason: "content: \(error)", at: path))
            }
            recordIDs(type, value: text, at: path)
        case let .elementOnly(particle):
            rejectText(element, at: path, into: &errors)
            shallowStructure(particle, children: children, at: path, into: &errors)
        case let .mixed(particle):
            shallowStructure(particle, children: children, at: path, into: &errors)
        }
    }

    private func shallowStructure(_ particle: PureXML.Schema.Particle, children: [PureXML.Model.Element], at path: XSDPath, into errors: inout [XSDFailure]) {
        if case let .group(group) = particle.term, group.compositor == .all {
            allStructureErrors(group, children: children, groupOptional: particle.occurrenceRange.minimum.isZero, at: path, into: &errors)
        } else {
            sequenceStructureErrors(particle, children: children, at: path, into: &errors)
        }
    }
}
