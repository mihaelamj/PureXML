/// File-scope aliases for the XSD complex-type validator, kept out of the
/// namespace to avoid nesting a type two levels deep.
typealias XSDFailure = PureXML.Validation.ValidationError
typealias XSDPath = [PureXML.Validation.PathKey]
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
        /// Derivation methods each element declaration forbids through `xsi:type`
        /// (the `block` on the element, distinct from the block on its type).
        let elementBlock: [String: Set<DerivationMethod>]
        /// Each named complex type's base and derivation method.
        let typeDerivation: [String: TypeDerivation]

        public init(
            types: [String: ElementType] = [:],
            nillableElements: Set<String> = [],
            elementConstraints: [String: ValueConstraint] = [:],
            abstractTypes: Set<String> = [],
            typeBlock: [String: Set<DerivationMethod>] = [:],
            elementBlock: [String: Set<DerivationMethod>] = [:],
            typeDerivation: [String: TypeDerivation] = [:],
        ) {
            self.types = types
            self.nillableElements = nillableElements
            self.elementConstraints = elementConstraints
            self.abstractTypes = abstractTypes
            self.typeBlock = typeBlock
            self.elementBlock = elementBlock
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
        func nilErrors(_ element: PureXML.Model.Element, at path: XSDPath) -> [XSDFailure]? {
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
        func elementFixedErrors(_ element: PureXML.Model.Element, at path: XSDPath) -> [XSDFailure] {
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

        func validateAttributes(
            _ element: PureXML.Model.Element,
            _ type: ComplexType,
            at path: XSDPath,
            into errors: inout [XSDFailure],
        ) {
            let present = element.attributes.filter { !Self.isNamespaceDeclaration($0) && !Self.isSchemaInstanceAttribute($0) }
            for use in type.attributes {
                let match = present.first { Self.sameName($0.name, use.name) }
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
            for attribute in present where !type.attributes.contains(where: { Self.sameName($0.name, attribute.name) }) {
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

        func rejectText(_ element: PureXML.Model.Element, at path: XSDPath, into errors: inout [XSDFailure]) {
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
            // Locate each content-model violation at the offending child (or the
            // missing one), with a recovery hint, rather than one opaque failure,
            // then still validate every well-placed child's own content.
            if case let .group(group) = particle.term, group.compositor == .all {
                allStructureErrors(group, children: children, at: path, into: &errors)
            } else {
                sequenceStructureErrors(particle, children: children, at: path, into: &errors)
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
            guard let declared = overriddenType(declared, for: child, at: path, into: &errors) else { return }
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
            case .typeReference:
                validateResolvedReference(declared, child, at: path, into: &errors)
            }
        }

        /// The declared type after an `xsi:type` override. An override naming an
        /// undeclared type appends an error and returns nil, not a silent fallback
        /// to the declared type.
        private func overriddenType(
            _ declared: ElementType,
            for child: PureXML.Model.Element,
            at path: XSDPath,
            into errors: inout [XSDFailure],
        ) -> ElementType? {
            guard let overriding = Self.xsiTypeName(child) else { return declared }
            guard let resolved = types[overriding] else {
                errors.append(XSDFailure(reason: "unknown xsi:type '\(overriding)' on '\(child.name.localName)'", at: path))
                return nil
            }
            return resolved
        }

        /// Validates a child against a `typeReference` through the shared resolver,
        /// reporting an unknown name or a circular chain as a located error.
        private func validateResolvedReference(
            _ declared: ElementType,
            _ child: PureXML.Model.Element,
            at path: XSDPath,
            into errors: inout [XSDFailure],
        ) {
            switch resolveReference(declared) {
            case let .unknown(name):
                errors.append(XSDFailure(reason: "unknown type '\(name)'", at: path))
            case let .circular(name):
                errors.append(XSDFailure(reason: "circular type reference '\(name)'", at: path))
            case let .resolved(resolved):
                validateChild(child, against: resolved, at: path, into: &errors)
            }
        }
    }
}

/// Located content-model diagnostics: pinpoint which child breaks the model and
/// what was expected there, so an editor shows placed errors with recovery hints
/// rather than one opaque "content does not match" per element.
extension PureXML.Schema.ComplexValidator {
    /// Walks the children through the content automaton, flagging the first child
    /// the follow-set rejects, or the missing content when the sequence ends early.
    func sequenceStructureErrors(_ particle: PureXML.Schema.Particle, children: [PureXML.Model.Element], at path: XSDPath, into errors: inout [XSDFailure]) {
        let nfa = PureXML.Schema.ContentNFABuilder.build(particle)
        let steps = Self.childSteps(children)
        // Advance one active state-set across the children rather than re-walking
        // the prefix per child (which is quadratic over the content model, #129).
        var current = nfa.startStates()
        for (index, child) in children.enumerated() {
            guard let next = nfa.step(current, over: child.name) else {
                let allowed = nfa.admissible(from: current)
                errors.append(XSDFailure(reason: "element '\(child.name.localName)' is not allowed here\(Self.expectation(allowed))", at: path + [steps[index]]))
                return
            }
            current = next
        }
        if !nfa.isComplete(current) {
            errors.append(XSDFailure(reason: "content is incomplete\(Self.expectation(nfa.admissible(from: current)))", at: path))
        }
    }

    /// Locates `all`-group violations: each child that is not an in-bounds member,
    /// recovering past it, then each required member that never appeared.
    func allStructureErrors(_ group: PureXML.Schema.Group, children: [PureXML.Model.Element], at path: XSDPath, into errors: inout [XSDFailure]) {
        var counts = [Int](repeating: 0, count: group.particles.count)
        let steps = Self.childSteps(children)
        for (index, child) in children.enumerated() {
            guard let position = group.particles.indices.first(where: { slot in
                let member = group.particles[slot]
                let room = member.maxOccurs.map { counts[slot] < $0 } ?? true
                return room && Self.memberMatches(member.term, child.name)
            }) else {
                errors.append(XSDFailure(reason: "element '\(child.name.localName)' is not allowed here", at: path + [steps[index]]))
                continue
            }
            counts[position] += 1
        }
        for (index, member) in group.particles.enumerated() where counts[index] < member.minOccurs {
            if case let .element(name, _) = member.term {
                errors.append(XSDFailure(reason: "element '\(name.localName)' is required but missing", at: path))
            }
        }
    }

    static func memberMatches(_ term: PureXML.Schema.Term, _ name: PureXML.Model.QualifiedName) -> Bool {
        switch term {
        case let .element(declared, _): declared.localName == name.localName && declared.namespaceURI == name.namespaceURI
        case let .wildcard(wildcard): wildcard.admits(name)
        case .group: false
        }
    }

    /// A "; expected a, b" hint naming the elements the automaton accepts next.
    static func expectation(_ labels: [PureXML.Schema.TermLabel]) -> String {
        let names = labels.compactMap { label -> String? in
            if case let .name(qualified) = label { return "<\(qualified.localName)>" }
            return nil
        }
        let unique = Set(names).sorted()
        return unique.isEmpty ? "" : "; expected \(unique.joined(separator: ", "))"
    }
}
