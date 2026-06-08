public extension PureXML.Schema {
    /// Validates an element against a ``ComplexType``: its attribute uses, its
    /// content model, and, recursively, each child element against the type
    /// declared for its name.
    struct ComplexValidator {
        /// The named type table that `ElementType.typeReference` resolves against.
        private let types: [String: ElementType]

        public init(types: [String: ElementType] = [:]) {
            self.types = types
        }

        /// Validates `element` against `type`, returning one issue per violation.
        public func validate(
            _ element: PureXML.Model.Element,
            against type: ComplexType,
        ) -> [PureXML.Validation.Issue] {
            var issues: [PureXML.Validation.Issue] = []
            validateAttributes(element, type, into: &issues)
            validateContent(element, type.content, into: &issues)
            return issues
        }

        /// Validates `element` against any element type, resolving a
        /// `typeReference` through the type table.
        public func validate(
            _ element: PureXML.Model.Element,
            as type: ElementType,
        ) -> [PureXML.Validation.Issue] {
            var issues: [PureXML.Validation.Issue] = []
            validateChild(element, against: type, into: &issues)
            return issues
        }

        // MARK: Attributes

        private func validateAttributes(
            _ element: PureXML.Model.Element,
            _ type: ComplexType,
            into issues: inout [PureXML.Validation.Issue],
        ) {
            let present = element.attributes.filter { !Self.isNamespaceDeclaration($0) && !Self.isSchemaInstanceAttribute($0) }
            for use in type.attributes {
                let match = present.first { $0.name.localName == use.name.localName }
                if let match {
                    if let error = use.type.validate(match.value) {
                        issues.append(.init(severity: .error, message: "attribute '\(use.name.localName)': \(error)"))
                    }
                } else if use.required {
                    issues.append(.init(severity: .error, message: "missing required attribute '\(use.name.localName)'"))
                }
            }
            guard !type.allowsOtherAttributes else { return }
            for attribute in present where !type.attributes.contains(where: { $0.name.localName == attribute.name.localName }) {
                issues.append(.init(severity: .error, message: "undeclared attribute '\(attribute.name.localName)'"))
            }
        }

        // MARK: Content

        private func validateContent(
            _ element: PureXML.Model.Element,
            _ content: ContentType,
            into issues: inout [PureXML.Validation.Issue],
        ) {
            let children = element.children.compactMap(\.element)
            switch content {
            case .empty:
                if !children.isEmpty { issues.append(.init(severity: .error, message: "element must be empty")) }
                rejectText(element, allowed: false, into: &issues)
            case let .simpleContent(type):
                if !children.isEmpty { issues.append(.init(severity: .error, message: "element must not have children")) }
                if let error = type.validate(Self.textContent(element)) {
                    issues.append(.init(severity: .error, message: "content: \(error)"))
                }
            case let .elementOnly(particle):
                rejectText(element, allowed: false, into: &issues)
                validateParticle(particle, children: children, into: &issues)
            case let .mixed(particle):
                validateParticle(particle, children: children, into: &issues)
            }
        }

        private func rejectText(
            _ element: PureXML.Model.Element,
            allowed: Bool,
            into issues: inout [PureXML.Validation.Issue],
        ) {
            guard !allowed, !Self.textContent(element).isEmpty else { return }
            issues.append(.init(severity: .error, message: "element must not contain text"))
        }

        // MARK: Particles

        private func validateParticle(
            _ particle: Particle,
            children: [PureXML.Model.Element],
            into issues: inout [PureXML.Validation.Issue],
        ) {
            let names = children.map(\.name)
            let structureValid: Bool = if case let .group(group) = particle.term, group.compositor == .all {
                Self.matchesAll(group, names: names)
            } else {
                ContentNFABuilder.build(particle).matchesWhole(names)
            }
            if !structureValid {
                issues.append(.init(severity: .error, message: "content does not match the content model"))
                return
            }
            validateChildren(children, childTypes: Self.elementTypes(in: particle.term), into: &issues)
        }

        private func validateChildren(
            _ children: [PureXML.Model.Element],
            childTypes: [String: ElementType],
            into issues: inout [PureXML.Validation.Issue],
        ) {
            for child in children {
                guard let declared = childTypes[Self.key(child.name)] else { continue }
                validateChild(child, against: declared, into: &issues)
            }
        }

        private func validateChild(
            _ child: PureXML.Model.Element,
            against declared: ElementType,
            into issues: inout [PureXML.Validation.Issue],
        ) {
            // An instance `xsi:type` overrides the declared type, provided the
            // named type exists in the schema. Resolve to the type itself rather
            // than a reference so re-entry does not re-read the same xsi:type.
            var declared = declared
            if let overriding = Self.xsiTypeName(child), let resolved = types[overriding] {
                declared = resolved
            }
            switch declared {
            case let .simple(simple):
                if !child.children.compactMap(\.element).isEmpty {
                    issues.append(.init(severity: .error, message: "'\(child.name.localName)' must not have children"))
                }
                if let error = simple.validate(Self.textContent(child)) {
                    issues.append(.init(severity: .error, message: "'\(child.name.localName)': \(error)"))
                }
            case let .complex(complex):
                issues.append(contentsOf: validate(child, against: complex))
            case let .typeReference(name):
                guard let resolved = types[name] else {
                    issues.append(.init(severity: .error, message: "unknown type '\(name)'"))
                    return
                }
                validateChild(child, against: resolved, into: &issues)
            }
        }

        // MARK: Helpers

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

        /// The local name of an element's `xsi:type` attribute value, or nil when
        /// it carries none. Recognizes the attribute by the XML Schema instance
        /// namespace or, failing namespace resolution, the conventional `xsi`
        /// prefix.
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
