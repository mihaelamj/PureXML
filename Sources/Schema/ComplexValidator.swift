/// File-scope aliases for the XSD complex-type validator, kept out of the
/// namespace to avoid nesting a type two levels deep.
private typealias XSDFailure = PureXML.Validation.ValidationError
private typealias XSDPath = [PureXML.Validation.PathKey]
private typealias XSDGroup = PureXML.Schema.Group
private typealias XSDTerm = PureXML.Schema.Term
private typealias XSDTermLabel = PureXML.Schema.TermLabel
private typealias XSDProcessContents = PureXML.Schema.ProcessContents
private typealias XSDElementType = PureXML.Schema.ElementType
private typealias XSDWildcard = PureXML.Schema.Wildcard

public extension PureXML.Schema {
    /// Validates an element against a ``ComplexType``: its attribute uses, its
    /// content model, and, recursively, each child element against the type
    /// declared for its name. Every violation is located by the element's coding
    /// path, and the results are ``PureXML/Validation/ValidationError`` values.
    struct ComplexValidator {
        /// The named type table that `ElementType.typeReference` resolves against.
        let types: [String: ElementType]
        /// Local names of elements declared `nillable="true"`.
        private let nillableElements: Set<String>
        /// The `default`/`fixed` value constraint declared on each element name.
        private let elementConstraints: [String: ValueConstraint]
        /// Local names of complex types declared `abstract="true"`.
        let abstractTypes: Set<String>
        /// Derivation methods each named type forbids through `xsi:type`.
        let typeBlock: [String: Set<DerivationMethod>]
        /// Each named complex type's base and derivation method.
        let typeDerivation: [String: TypeDerivation]

        public init(
            types: [String: ElementType] = [:],
            nillableElements: Set<String> = [],
            elementConstraints: [String: ValueConstraint] = [:],
            abstractTypes: Set<String> = [],
            typeBlock: [String: Set<DerivationMethod>] = [:],
            typeDerivation: [String: TypeDerivation] = [:],
        ) {
            self.types = types
            self.nillableElements = nillableElements
            self.elementConstraints = elementConstraints
            self.abstractTypes = abstractTypes
            self.typeBlock = typeBlock
            self.typeDerivation = typeDerivation
        }

        /// Validates `element` against `type` at `path`, one error per violation.
        public func validate(
            _ element: PureXML.Model.Element,
            against type: ComplexType,
            at path: [PureXML.Validation.PathKey] = [],
        ) -> [PureXML.Validation.ValidationError] {
            var errors: [XSDFailure] = []
            validateAttributes(element, type, at: path, into: &errors)
            // An xsi:nil element keeps its attribute obligations but must have no
            // content; its content model is not otherwise checked.
            if let nilErrors = nilErrors(element, at: path) {
                return errors + nilErrors
            }
            validateContent(element, type.content, at: path, into: &errors)
            errors += elementFixedErrors(element, at: path)
            return errors
        }

        /// The errors from an `xsi:nil="true"` element: rejecting it when the
        /// element is not nillable, or when it carries content. Returns nil when
        /// the element is not nilled.
        private func nilErrors(_ element: PureXML.Model.Element, at path: XSDPath) -> [XSDFailure]? {
            guard Self.isNil(element) else { return nil }
            let name = element.name.localName
            if !nillableElements.contains(name) {
                return [XSDFailure(reason: "element '\(name)' is not nillable but has xsi:nil", at: path)]
            }
            if Self.hasContent(element) {
                return [XSDFailure(reason: "nil element '\(name)' must be empty", at: path)]
            }
            return []
        }

        /// The error from a `fixed` element value constraint: the element's text
        /// must equal the fixed value.
        private func elementFixedErrors(_ element: PureXML.Model.Element, at path: XSDPath) -> [XSDFailure] {
            guard let fixed = elementConstraints[element.name.localName]?.fixedValue else { return [] }
            let text = Self.textContent(element)
            return text == fixed ? [] : [XSDFailure(reason: "element '\(element.name.localName)' is fixed and must be '\(fixed)'", at: path)]
        }

        /// Validates `element` against any element type at `path`, resolving a
        /// `typeReference` through the type table.
        public func validate(
            _ element: PureXML.Model.Element,
            as type: ElementType,
            at path: [PureXML.Validation.PathKey] = [],
        ) -> [PureXML.Validation.ValidationError] {
            var errors: [XSDFailure] = []
            validateChild(element, against: type, at: path, into: &errors)
            return errors
        }

        // MARK: Attributes

        private func validateAttributes(
            _ element: PureXML.Model.Element,
            _ type: ComplexType,
            at path: XSDPath,
            into errors: inout [XSDFailure],
        ) {
            let present = element.attributes.filter { !Self.isNamespaceDeclaration($0) && !Self.isSchemaInstanceAttribute($0) }
            for use in type.attributes {
                let match = present.first { $0.name.localName == use.name.localName }
                if let match {
                    if let error = use.type.validate(match.value) {
                        errors.append(XSDFailure(reason: "attribute '\(use.name.localName)': \(error)", at: path))
                    }
                    if let fixed = use.valueConstraint?.fixedValue, match.value != fixed {
                        errors.append(XSDFailure(reason: "attribute '\(use.name.localName)' is fixed and must be '\(fixed)'", at: path))
                    }
                } else if use.required {
                    errors.append(XSDFailure(reason: "missing required attribute '\(use.name.localName)'", at: path))
                }
            }
            // An undeclared attribute is allowed only if an xs:anyAttribute wildcard
            // admits its namespace.
            for attribute in present where !type.attributes.contains(where: { $0.name.localName == attribute.name.localName }) {
                if type.attributeWildcard?.admits(attribute.name) == true { continue }
                errors.append(XSDFailure(reason: "undeclared attribute '\(attribute.name.localName)'", at: path))
            }
        }

        // MARK: Content

        private func validateContent(
            _ element: PureXML.Model.Element,
            _ content: ContentType,
            at path: XSDPath,
            into errors: inout [XSDFailure],
        ) {
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
                validateParticle(particle, children: children, at: path, into: &errors)
            case let .mixed(particle):
                validateParticle(particle, children: children, at: path, into: &errors)
            }
        }

        private func rejectText(_ element: PureXML.Model.Element, at path: XSDPath, into errors: inout [XSDFailure]) {
            guard !Self.textContent(element).isEmpty else { return }
            errors.append(XSDFailure(reason: "element must not contain text", at: path))
        }

        // MARK: Particles

        private func validateParticle(
            _ particle: Particle,
            children: [PureXML.Model.Element],
            at path: XSDPath,
            into errors: inout [XSDFailure],
        ) {
            let names = children.map(\.name)
            let structureValid: Bool = if case let .group(group) = particle.term, group.compositor == .all {
                Self.matchesAll(group, names: names)
            } else {
                ContentNFABuilder.build(particle).matchesWhole(names)
            }
            if !structureValid {
                errors.append(XSDFailure(reason: "content does not match the content model", at: path))
                return
            }
            validateChildren(
                children,
                childTypes: Self.elementTypes(in: particle.term),
                wildcard: Self.wildcard(in: particle.term),
                at: path,
                into: &errors,
            )
        }

        private func validateChildren(
            _ children: [PureXML.Model.Element],
            childTypes: [String: ElementType],
            wildcard: ProcessContents?,
            at path: XSDPath,
            into errors: inout [XSDFailure],
        ) {
            let steps = Self.childSteps(children)
            for (child, step) in zip(children, steps) {
                if let declared = childTypes[Self.key(child.name)] {
                    validateChild(child, against: declared, at: path + [step], into: &errors)
                } else if let wildcard {
                    // The structure already matched, so an undeclared child here was
                    // admitted by a wildcard; process its content per the wildcard.
                    validateWildcardChild(child, processContents: wildcard, at: path + [step], into: &errors)
                }
            }
        }

        /// Validates a wildcard-matched child by its `processContents`: skip does
        /// nothing, lax validates against a global declaration when one exists, and
        /// strict requires one.
        private func validateWildcardChild(
            _ child: PureXML.Model.Element,
            processContents: ProcessContents,
            at path: XSDPath,
            into errors: inout [XSDFailure],
        ) {
            switch processContents {
            case .skip:
                return
            case .lax:
                if let declaration = types["element:\(child.name.localName)"] {
                    validateChild(child, against: declaration, at: path, into: &errors)
                }
            case .strict:
                guard let declaration = types["element:\(child.name.localName)"] else {
                    errors.append(XSDFailure(reason: "no declaration for wildcard-matched element '\(child.name.localName)'", at: path))
                    return
                }
                validateChild(child, against: declaration, at: path, into: &errors)
            }
        }

        private func validateChild(
            _ child: PureXML.Model.Element,
            against declared: ElementType,
            at path: XSDPath,
            into errors: inout [XSDFailure],
        ) {
            // An instance `xsi:type` overrides the declared type, provided the named
            // type exists in the schema. Resolve to the type itself rather than a
            // reference so re-entry does not re-read the same xsi:type. A `block` on
            // the declared type can forbid the substitution; an abstract declared
            // type requires one.
            if let blocked = blockedSubstitutionError(declared: declared, child: child, at: path) {
                errors.append(blocked)
                return
            }
            if case let .typeReference(name) = declared, let missing = abstractTypeError(named: name, child: child, at: path) {
                errors.append(missing)
                return
            }
            var declared = declared
            if let overriding = Self.xsiTypeName(child), let resolved = types[overriding] {
                declared = resolved
            }
            switch declared {
            case let .simple(simple):
                if let nilErrors = nilErrors(child, at: path) {
                    errors += nilErrors
                    return
                }
                if !child.children.compactMap(\.element).isEmpty {
                    errors.append(XSDFailure(reason: "'\(child.name.localName)' must not have children", at: path))
                }
                if let error = simple.validate(Self.textContent(child)) {
                    errors.append(XSDFailure(reason: "'\(child.name.localName)': \(error)", at: path))
                }
                errors += elementFixedErrors(child, at: path)
            case let .complex(complex):
                errors.append(contentsOf: validate(child, against: complex, at: path))
            case let .typeReference(name):
                guard let resolved = types[name] else {
                    errors.append(XSDFailure(reason: "unknown type '\(name)'", at: path))
                    return
                }
                validateChild(child, against: resolved, at: path, into: &errors)
            }
        }
    }
}
