/// File-scope aliases for the XSD complex-type validator, kept out of the
/// namespace to avoid nesting a type two levels deep.
private typealias XSDFailure = PureXML.Validation.ValidationError
private typealias XSDPath = [PureXML.Validation.PathKey]

public extension PureXML.Schema {
    /// Validates an element against a ``ComplexType``: its attribute uses, its
    /// content model, and, recursively, each child element against the type
    /// declared for its name. Every violation is located by the element's coding
    /// path, and the results are ``PureXML/Validation/ValidationError`` values.
    struct ComplexValidator {
        /// The named type table that `ElementType.typeReference` resolves against.
        private let types: [String: ElementType]

        public init(types: [String: ElementType] = [:]) {
            self.types = types
        }

        /// Validates `element` against `type` at `path`, one error per violation.
        public func validate(
            _ element: PureXML.Model.Element,
            against type: ComplexType,
            at path: [PureXML.Validation.PathKey] = [],
        ) -> [PureXML.Validation.ValidationError] {
            var errors: [XSDFailure] = []
            validateAttributes(element, type, at: path, into: &errors)
            validateContent(element, type.content, at: path, into: &errors)
            return errors
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
                } else if use.required {
                    errors.append(XSDFailure(reason: "missing required attribute '\(use.name.localName)'", at: path))
                }
            }
            guard !type.allowsOtherAttributes else { return }
            for attribute in present where !type.attributes.contains(where: { $0.name.localName == attribute.name.localName }) {
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
            validateChildren(children, childTypes: Self.elementTypes(in: particle.term), at: path, into: &errors)
        }

        private func validateChildren(
            _ children: [PureXML.Model.Element],
            childTypes: [String: ElementType],
            at path: XSDPath,
            into errors: inout [XSDFailure],
        ) {
            let steps = Self.childSteps(children)
            for (child, step) in zip(children, steps) {
                guard let declared = childTypes[Self.key(child.name)] else { continue }
                validateChild(child, against: declared, at: path + [step], into: &errors)
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
            // reference so re-entry does not re-read the same xsi:type.
            var declared = declared
            if let overriding = Self.xsiTypeName(child), let resolved = types[overriding] {
                declared = resolved
            }
            switch declared {
            case let .simple(simple):
                if !child.children.compactMap(\.element).isEmpty {
                    errors.append(XSDFailure(reason: "'\(child.name.localName)' must not have children", at: path))
                }
                if let error = simple.validate(Self.textContent(child)) {
                    errors.append(XSDFailure(reason: "'\(child.name.localName)': \(error)", at: path))
                }
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

        // MARK: Helpers

        /// The coding-path step for each child: its name, with a sibling index only
        /// when more than one child shares that name.
        private static func childSteps(_ children: [PureXML.Model.Element]) -> [PureXML.Validation.PathKey] {
            var totals: [String: Int] = [:]
            for child in children {
                totals[child.name.description, default: 0] += 1
            }
            var seen: [String: Int] = [:]
            return children.map { child in
                let name = child.name.description
                let index = (seen[name] ?? 0) + 1
                seen[name] = index
                return (totals[name] ?? 0) > 1 ? .element(name, index: index) : .element(name)
            }
        }

        /// Validates an `all` group order-independently: every child matches a
        /// member within its occurrence bounds, and each member meets its minimum.
        private static func matchesAll(_ group: Group, names: [PureXML.Model.QualifiedName]) -> Bool {
            var counts = [Int](repeating: 0, count: group.particles.count)
            for name in names {
                guard let index = group.particles.indices.first(where: { position in
                    let member = group.particles[position]
                    let room = member.maxOccurs.map { counts[position] < $0 } ?? true
                    return room && label(of: member.term).matches(name)
                }) else { return false }
                counts[index] += 1
            }
            for (index, member) in group.particles.enumerated() where counts[index] < member.minOccurs {
                return false
            }
            return true
        }

        private static func label(of term: Term) -> TermLabel {
            if case let .element(name, _) = term { return .name(name) }
            return .any
        }

        private static func elementTypes(in term: Term) -> [String: ElementType] {
            var result: [String: ElementType] = [:]
            collectTypes(term, into: &result)
            return result
        }

        private static func collectTypes(_ term: Term, into result: inout [String: ElementType]) {
            switch term {
            case let .element(name, type):
                if let type { result[key(name)] = type }
            case let .group(group):
                for member in group.particles {
                    collectTypes(member.term, into: &result)
                }
            case .wildcard:
                break
            }
        }

        private static func key(_ name: PureXML.Model.QualifiedName) -> String {
            "{\(name.namespaceURI ?? "")}\(name.localName)"
        }

        private static func textContent(_ element: PureXML.Model.Element) -> String {
            let text = element.children.reduce(into: "") { result, child in
                switch child {
                case let .text(value), let .cdata(value): result += value
                default: break
                }
            }
            return text.trimmingXMLWhitespace()
        }

        private static func isNamespaceDeclaration(_ attribute: PureXML.Model.Attribute) -> Bool {
            attribute.name.prefix == "xmlns" || (attribute.name.prefix == nil && attribute.name.localName == "xmlns")
        }

        /// Whether an attribute belongs to the XML Schema instance namespace
        /// (`xsi:type`, `xsi:nil`, and the schema-location hints), which are
        /// processing directives rather than declared attributes.
        private static func isSchemaInstanceAttribute(_ attribute: PureXML.Model.Attribute) -> Bool {
            attribute.name.namespaceURI == "http://www.w3.org/2001/XMLSchema-instance" || attribute.name.prefix == "xsi"
        }

        /// The local name of an element's `xsi:type` attribute value, or nil when it
        /// carries none. Recognizes the attribute by the XML Schema instance
        /// namespace or, failing namespace resolution, the conventional `xsi` prefix.
        private static func xsiTypeName(_ element: PureXML.Model.Element) -> String? {
            let schemaInstance = "http://www.w3.org/2001/XMLSchema-instance"
            let match = element.attributes.first { attribute in
                attribute.name.localName == "type"
                    && (attribute.name.namespaceURI == schemaInstance || attribute.name.prefix == "xsi")
            }
            return match.map { $0.value.split(separator: ":").last.map(String.init) ?? $0.value }
        }
    }
}
