public extension PureXML.Schema {
    /// An element paired with its already-resolved effective type: the subject of
    /// the streaming XSD content rule, so the contextual type resolution that a
    /// node-tree walk cannot express is carried on the subject instead.
    struct ResolvedElement: PureXML.Validation.Validatable {
        public let element: PureXML.Model.Element
        public let type: ElementType

        public init(element: PureXML.Model.Element, type: ElementType) {
            self.element = element
            self.type = type
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
            context.document.validateShallow(context.subject.element, as: context.subject.type, at: context.codingPath)
        }
    }

    /// The effective element type after an `xsi:type` override and following any
    /// `typeReference` chain, so the streaming driver resolves a type once per
    /// element rather than re-entering the tree walk.
    func effectiveType(_ declared: PureXML.Schema.ElementType, of element: PureXML.Model.Element) -> PureXML.Schema.ElementType {
        var type = declared
        if let overriding = Self.xsiTypeName(element), let resolved = types[overriding] {
            type = resolved
        }
        // An unknown or circular chain stays a typeReference, which
        // validateShallow reports as a located error.
        if case let .resolved(resolved) = resolveReference(type) {
            type = resolved
        }
        return type
    }

    /// The declared element type of a child `name` in `parent`'s content model, or
    /// nil when the parent has no element content or no such child (an undeclared
    /// child is flagged by the parent's own structure check).
    func childType(of parent: PureXML.Schema.ElementType, child name: PureXML.Model.QualifiedName) -> PureXML.Schema.ElementType? {
        guard case let .complex(complex) = parent else { return nil }
        switch complex.content {
        case let .elementOnly(particle), let .mixed(particle):
            return Self.elementTypes(in: particle.term)[Self.key(name)]
        case .empty, .simpleContent:
            return nil
        }
    }

    /// Validates one element's own attributes and content-model structure (child
    /// names, order, occurrence) and simple content, but not its children's own
    /// validity, which the streaming driver checks as each child closes. `type`
    /// must already be effective (see ``effectiveType(_:of:)``).
    func validateShallow(
        _ element: PureXML.Model.Element,
        as type: PureXML.Schema.ElementType,
        at path: [PureXML.Validation.PathKey] = [],
    ) -> [PureXML.Validation.ValidationError] {
        var errors: [XSDFailure] = []
        switch type {
        case let .simple(simple):
            validateSimpleElement(element, simple, at: path, into: &errors)
        case let .complex(complex):
            validateAttributes(element, complex, at: path, into: &errors)
            if let nilErrors = nilErrors(element, at: path) { return errors + nilErrors }
            shallowContent(element, complex.content, at: path, into: &errors)
            errors += elementFixedErrors(element, at: path)
        case .typeReference:
            // The shared resolver also guards a circular chain, which would
            // otherwise recurse here without terminating.
            switch resolveReference(type) {
            case let .unknown(name):
                return [XSDFailure(reason: "unknown type '\(name)'", at: path)]
            case let .circular(name):
                return [XSDFailure(reason: "circular type reference '\(name)'", at: path)]
            case let .resolved(resolved):
                return validateShallow(element, as: resolved, at: path)
            }
        }
        return errors
    }

    private func validateSimpleElement(_ element: PureXML.Model.Element, _ simple: PureXML.Schema.SimpleType, at path: XSDPath, into errors: inout [XSDFailure]) {
        if let nilErrors = nilErrors(element, at: path) {
            errors += nilErrors
            return
        }
        if !element.children.compactMap(\.element).isEmpty {
            errors.append(XSDFailure(reason: "'\(element.name.localName)' must not have children", at: path))
        }
        if let error = simple.validate(Self.textContent(element)) {
            errors.append(XSDFailure(reason: "'\(element.name.localName)': \(error)", at: path))
        }
        errors += elementFixedErrors(element, at: path)
    }

    private func shallowContent(_ element: PureXML.Model.Element, _ content: PureXML.Schema.ContentType, at path: XSDPath, into errors: inout [XSDFailure]) {
        let children = element.children.compactMap(\.element)
        switch content {
        case .empty:
            if !children.isEmpty { errors.append(XSDFailure(reason: "element must be empty", at: path)) }
            rejectText(element, at: path, into: &errors)
        case let .simpleContent(type):
            if !children.isEmpty { errors.append(XSDFailure(reason: "element must not have children", at: path)) }
            if let error = type.validate(Self.textContent(element)) {
                errors.append(XSDFailure(reason: "content: \(error)", at: path))
            }
        case let .elementOnly(particle):
            rejectText(element, at: path, into: &errors)
            shallowStructure(particle, children: children, at: path, into: &errors)
        case let .mixed(particle):
            shallowStructure(particle, children: children, at: path, into: &errors)
        }
    }

    private func shallowStructure(_ particle: PureXML.Schema.Particle, children: [PureXML.Model.Element], at path: XSDPath, into errors: inout [XSDFailure]) {
        if case let .group(group) = particle.term, group.compositor == .all {
            allStructureErrors(group, children: children, at: path, into: &errors)
        } else {
            sequenceStructureErrors(particle, children: children, at: path, into: &errors)
        }
    }
}
