/// File-scope aliases for the XSD complex-type validator, kept out of the
/// namespace to avoid nesting a type two levels deep.
typealias XSDFailure = PureXML.Validation.ValidationError
typealias XSDPath = [PureXML.Validation.PathKey]
private struct XSDChildValidationFrame {
    let path: XSDPath
    let namespaceBindings: [String: String]
}

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
        /// Complex types declared `abstract="true"`, keyed by namespaced identity
        /// (`{ns}local`) so same-local-name types in different namespaces stay distinct.
        let abstractTypes: Set<String>
        /// Derivation methods each named type forbids through `xsi:type`, keyed by
        /// namespaced identity (`{ns}local`).
        let typeBlock: [String: Set<DerivationMethod>]
        /// Derivation methods each element declaration forbids through `xsi:type`
        /// (the `block` on the element, distinct from the block on its type), keyed by
        /// namespaced identity (`{ns}local`).
        let elementBlock: [String: Set<DerivationMethod>]
        /// Each named complex type's base and derivation method, keyed by namespaced
        /// identity (`{ns}local`).
        let typeDerivation: [String: TypeDerivation]
        /// Global attribute declarations for strict/lax `anyAttribute` validation.
        let globalAttributes: [String: AttributeUse]
        /// Document-scoped xs:ID/xs:IDREF accumulator, filled during the typed walk
        /// and reported by `idErrors()` once the whole tree has been seen. See the
        /// ID/IDREF extension for `idErrors()` and `recordIDs(_:value:at:)`.
        let idTracker = IDTracker()

        public init(
            types: [String: ElementType] = [:],
            globalAttributes: [String: AttributeUse] = [:],
            nillableElements: Set<String> = [],
            elementConstraints: [String: ValueConstraint] = [:],
            abstractTypes: Set<String> = [],
            typeBlock: [String: Set<DerivationMethod>] = [:],
            elementBlock: [String: Set<DerivationMethod>] = [:],
            typeDerivation: [String: TypeDerivation] = [:],
        ) {
            self.types = types
            self.globalAttributes = globalAttributes
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
            namespaceBindings inheritedBindings: [String: String] = [:],
        ) -> [PureXML.Validation.ValidationError] {
            let namespaceBindings = Self.namespaceBindings(for: element, inherited: inheritedBindings)
            var errors: [XSDFailure] = []
            validateAttributes(element, type, at: path, into: &errors)
            // An xsi:nil element keeps its attribute obligations but must have no
            // content; its content model is not otherwise checked.
            if let nilErrors = nilErrors(element, at: path) {
                return errors + nilErrors
            }
            validateContent(element, type.content, at: path, namespaceBindings: namespaceBindings, into: &errors)
            // A simpleContent fixed value is compared in its simple type's value space
            // (cvc-elt.5.2.2.1), e.g. "05" equals an xs:int fixed "5".
            let simpleContentType: SimpleType? = if case let .simpleContent(simple) = type.content { simple } else { nil }
            errors += elementFixedErrors(element, valueType: simpleContentType, at: path)
            return errors
        }

        /// The errors from an `xsi:nil="true"` element: rejecting it when the
        /// element is not nillable, or when it carries content. Returns nil when
        /// the element is not nilled.
        func nilErrors(_ element: PureXML.Model.Element, fixedValue: String? = nil, at path: XSDPath) -> [XSDFailure]? {
            let name = element.name.localName
            // cvc-elt.3.1: a non-nillable element must carry no `xsi:nil` attribute at
            // all, whatever its value (so `xsi:nil="false"` is equally forbidden, not
            // only `xsi:nil="true"`).
            if Self.nilAttributeValue(element) != nil, !nillableElements.contains(name) {
                return [XSDFailure(reason: "element '\(name)' is not nillable but has xsi:nil", at: path)]
            }
            guard Self.isNil(element) else { return nil }
            if Self.hasContent(element) {
                return [XSDFailure(reason: "nil element '\(name)' must be empty", at: path)]
            }
            // cvc-elt.3.2.2: a nilled element may not have a fixed {value constraint}.
            // The matched particle's constraint is authoritative; the by-local-name map
            // is a fallback for paths without a particle (e.g. the resolved-type entry).
            if (fixedValue ?? elementConstraints[name]?.fixedValue) != nil {
                return [XSDFailure(reason: "nil element '\(name)' must not have a fixed value constraint", at: path)]
            }
            return []
        }

        /// The text an element's simple content is validated against: its character
        /// content, or, when the element is empty, its `default`/`fixed` value (an
        /// empty element takes that value, and the value, not the empty string, must
        /// satisfy the type). The matched particle's constraint takes precedence over
        /// the by-local-name `elementConstraints` map, exactly as the tree path's
        /// `validateChild` resolves it.
        func effectiveSimpleText(for element: PureXML.Model.Element, particleConstraint: ValueConstraint? = nil) -> String {
            let text = Self.rawTextContent(element)
            let constraint = particleConstraint ?? elementConstraints[element.name.localName]
            return text.isEmpty ? (constraint?.value ?? text) : text
        }

        /// The error from a `fixed` element value constraint: the element's text
        /// must equal the fixed value in the element type's value space when known.
        func elementFixedErrors(
            _ element: PureXML.Model.Element,
            valueType: SimpleType? = nil,
            particleFixed: String? = nil,
            at path: XSDPath,
        ) -> [XSDFailure] {
            guard let fixed = particleFixed ?? elementConstraints[element.name.localName]?.fixedValue else { return [] }
            // A fixed element's content is its fixed character value: it may not carry
            // element children, even under a mixed content type (cvc-elt.5.2.2.2.1).
            if !element.children.compactMap(\.element).isEmpty {
                return [XSDFailure(reason: "fixed element '\(element.name.localName)' must not have element children", at: path)]
            }
            let text = Self.rawTextContent(element)
            // An empty element takes the fixed value; only present content must equal it.
            if text.isEmpty { return [] }
            if let valueType, valueType.valueMatches(text, literal: fixed) { return [] }
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
            let namespaceBindings = Self.namespaceBindings(for: element)
            validateChild(element, against: type, at: path, namespaceBindings: namespaceBindings, into: &errors)
            return errors
        }

        // MARK: Content

        private func validateContent(
            _ element: PureXML.Model.Element,
            _ content: ContentType,
            at path: XSDPath,
            namespaceBindings: [String: String],
            into errors: inout [XSDFailure],
        ) {
            let children = element.children.compactMap(\.element)
            switch content {
            case .empty:
                if !children.isEmpty { errors.append(XSDFailure(reason: "element must be empty", at: path)) }
                rejectText(element, at: path, into: &errors)
            case let .simpleContent(type):
                if !children.isEmpty { errors.append(XSDFailure(reason: "element must not have children", at: path)) }
                if let error = type.validate(Self.rawTextContent(element)) {
                    errors.append(XSDFailure(reason: "content: \(error)", at: path))
                }
            case let .elementOnly(particle):
                rejectText(element, at: path, into: &errors)
                validateParticle(particle, children: children, at: path, namespaceBindings: namespaceBindings, into: &errors)
            case let .mixed(particle):
                validateParticle(particle, children: children, at: path, namespaceBindings: namespaceBindings, into: &errors)
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
            namespaceBindings: [String: String],
            into errors: inout [XSDFailure],
        ) {
            // Locate each content-model violation at the offending child (or the
            // missing one), with a recovery hint, rather than one opaque failure,
            // then assess every well-placed child against the exact particle the
            // content model matched it to (#180), not a by-name lookup that loses
            // which of two same-named particles, or a wildcard versus a named
            // particle, actually matched.
            let matched: [PureXML.Schema.MatchedParticle?]
            if case let .group(group) = particle.term, group.compositor == .all {
                allStructureErrors(group, children: children, groupOptional: particle.occurrenceRange.minimum.isZero, at: path, into: &errors)
                matched = allMatchedParticles(group, children: children)
            } else {
                sequenceStructureErrors(particle, children: children, at: path, into: &errors)
                matched = PureXML.Schema.ContentNFABuilder.build(particle).matchedParticles(children.map(\.name))
            }
            validateChildren(
                children,
                matched: matched,
                frame: XSDChildValidationFrame(path: path, namespaceBindings: namespaceBindings),
                into: &errors,
            )
        }

        private func validateChildren(
            _ children: [PureXML.Model.Element],
            matched: [PureXML.Schema.MatchedParticle?],
            frame: XSDChildValidationFrame,
            into errors: inout [XSDFailure],
        ) {
            let steps = Self.childSteps(children)
            for (index, child) in children.enumerated() {
                let namespaceBindings = Self.namespaceBindings(for: child, inherited: frame.namespaceBindings)
                let path = frame.path + [steps[index]]
                switch matched[index] {
                case let .element(type, valueConstraint):
                    // An element particle without an inlined type (a bare ref)
                    // resolves through its global declaration, as before.
                    guard let declared = type ?? globalElementDeclaration(for: child.name) else { continue }
                    validateChild(child, against: declared, at: path, namespaceBindings: namespaceBindings, particleConstraint: valueConstraint, into: &errors)
                case let .wildcard(wildcard):
                    validateWildcardChild(child, processContents: wildcard.processContents, at: path, namespaceBindings: namespaceBindings, into: &errors)
                case .none:
                    // The content model rejected this child (a structure error,
                    // already located above); the matched particle is undefined.
                    continue
                }
            }
        }

        /// Validates a wildcard-matched child by its `processContents`: skip does
        /// nothing, lax validates against a global declaration when one exists, and
        /// strict requires one.
        private func globalElementDeclaration(for name: PureXML.Model.QualifiedName) -> PureXML.Schema.ElementType? {
            // A global element declaration is always in the schema's target
            // namespace, so an instance element matches one only by full qualified
            // name. The namespaced key already covers a no-namespace global (its key
            // is `element:{}local`); matching an unqualified instance against a
            // namespaced global by bare local name would conflate namespaces, e.g.
            // accepting unqualified text where a namespaced `xs:short` is declared.
            types[PureXML.Schema.XSDParser.elementDeclarationKey(name)]
        }

        private func validateWildcardChild(
            _ child: PureXML.Model.Element,
            processContents: ProcessContents,
            at path: XSDPath,
            namespaceBindings: [String: String],
            into errors: inout [XSDFailure],
        ) {
            switch processContents {
            case .skip:
                return
            case .lax:
                if let declaration = globalElementDeclaration(for: child.name) {
                    validateChild(child, against: declaration, at: path, namespaceBindings: namespaceBindings, into: &errors)
                }
            case .strict:
                if let declaration = globalElementDeclaration(for: child.name) {
                    validateChild(child, against: declaration, at: path, namespaceBindings: namespaceBindings, into: &errors)
                } else if let type = xsiDeclaredType(for: child, namespaceBindings: namespaceBindings) {
                    validateChild(child, against: type, at: path, namespaceBindings: namespaceBindings, into: &errors)
                } else {
                    errors.append(XSDFailure(reason: "no declaration for wildcard-matched element '\(child.name.localName)'", at: path))
                }
            }
        }

        /// The type named by a wildcard-matched element's `xsi:type`, when present.
        private func xsiDeclaredType(for child: PureXML.Model.Element, namespaceBindings: [String: String]) -> ElementType? {
            guard Self.xsiTypeAttributeValue(child) != nil else { return nil }
            guard let reference = Self.xsiTypeReference(child, namespaceBindings: namespaceBindings),
                  let type = Self.resolveNamedType(reference, in: types)
            else { return nil }
            return type
        }

        private func validateChild(
            _ child: PureXML.Model.Element,
            against declared: ElementType,
            at path: XSDPath,
            namespaceBindings: [String: String],
            particleConstraint: ValueConstraint? = nil,
            into errors: inout [XSDFailure],
        ) {
            // An instance `xsi:type` overrides the declared type, provided the named
            // type exists in the schema. Resolve to the type itself rather than a
            // reference so re-entry does not re-read the same xsi:type. A `block` on
            // the declared type can forbid the substitution; an abstract declared
            // type requires one.
            if let xsiError = xsiTypeOverrideError(declared: declared, child: child, at: path, namespaceBindings: namespaceBindings) {
                errors.append(xsiError)
                return
            }
            guard let declared = overriddenType(declared, for: child, namespaceBindings: namespaceBindings, at: path, into: &errors) else { return }
            switch declared {
            case let .simple(simple):
                // A simple type declares no attribute uses, so a simple-typed
                // element (including one whose simple type comes from an xsi:type
                // override, and including a nilled one) may carry only the
                // schema-instance and namespace attributes; any other is a
                // violation. Checked before the nil short-circuit, since an
                // xsi:nil element is equally bound by it.
                for attribute in child.attributes where !Self.isNamespaceDeclaration(attribute) && !Self.isSchemaInstanceAttribute(attribute) {
                    errors.append(XSDFailure(reason: "'\(child.name.localName)' has a simple type and must not carry attribute '\(attribute.name.localName)'", at: path))
                }
                if let nilErrors = nilErrors(child, fixedValue: particleConstraint?.fixedValue, at: path) {
                    errors += nilErrors
                    return
                }
                if !child.children.compactMap(\.element).isEmpty {
                    errors.append(XSDFailure(reason: "'\(child.name.localName)' must not have children", at: path))
                }
                // An empty element takes its `default`/`fixed` value; that value
                // (not the empty string) is what must be valid against the type,
                // including any xsi:type override already resolved into `simple`.
                let text = Self.rawTextContent(child)
                if let error = simple.validate(effectiveSimpleText(for: child, particleConstraint: particleConstraint)) {
                    errors.append(XSDFailure(reason: "'\(child.name.localName)': \(error)", at: path))
                }
                recordIDs(simple, value: text, at: path)
                errors += elementFixedErrors(child, valueType: simple, particleFixed: particleConstraint?.fixedValue, at: path)
            case let .complex(complex):
                errors.append(contentsOf: validate(child, against: complex, at: path, namespaceBindings: namespaceBindings))
            case .typeReference:
                validateResolvedReference(declared, child, at: path, namespaceBindings: namespaceBindings, into: &errors)
            }
        }

        /// Validates a child against a `typeReference` through the shared resolver,
        /// reporting an unknown name or a circular chain as a located error.
        private func validateResolvedReference(
            _ declared: ElementType,
            _ child: PureXML.Model.Element,
            at path: XSDPath,
            namespaceBindings: [String: String],
            into errors: inout [XSDFailure],
        ) {
            switch resolveReference(declared) {
            case let .unknown(name):
                errors.append(XSDFailure(reason: "unknown type '\(name)'", at: path))
            case let .circular(name):
                errors.append(XSDFailure(reason: "circular type reference '\(name)'", at: path))
            case let .resolved(resolved):
                validateChild(child, against: resolved, at: path, namespaceBindings: namespaceBindings, into: &errors)
            }
        }
    }
}
