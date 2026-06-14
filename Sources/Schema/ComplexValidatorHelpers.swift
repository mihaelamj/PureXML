/// File-scope aliases for the complex-type validator's helpers, kept out of the
/// namespace to avoid nesting a type two levels deep in a dotted extension.
private typealias XSDTerm = PureXML.Schema.Term
private typealias XSDTermLabel = PureXML.Schema.TermLabel
private typealias XSDElementType = PureXML.Schema.ElementType
private typealias XSDWildcard = PureXML.Schema.Wildcard

extension PureXML.Schema.ComplexValidator {
    // MARK: Helpers

    /// The coding-path step for each child: its name, with a sibling index only
    /// when more than one child shares that name.
    static func childSteps(_ children: [PureXML.Model.Element]) -> [PureXML.Validation.PathKey] {
        PureXML.Validation.PathKey.steps(forChildNames: children.map(\.name.description))
    }

    /// Validates an `all` group order-independently: every child matches a
    /// member within its occurrence bounds, and each member meets its minimum.
    static func matchesAll(_ group: PureXML.Schema.Group, names: [PureXML.Model.QualifiedName]) -> Bool {
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

    fileprivate static func label(of term: XSDTerm) -> XSDTermLabel {
        switch term {
        case let .element(name, _, _): .name(name)
        case let .wildcard(wildcard): .wildcard(wildcard)
        case .group: .wildcard(XSDWildcard())
        }
    }

    /// The `processContents` of a wildcard reachable in `term`, if the content
    /// model contains one.
    static func wildcard(in term: PureXML.Schema.Term) -> PureXML.Schema.ProcessContents? {
        switch term {
        case let .wildcard(wildcard):
            return wildcard.processContents
        case let .group(group):
            for member in group.particles {
                if let found = wildcard(in: member.term) { return found }
            }
            return nil
        case .element:
            return nil
        }
    }

    static func elementTypes(in term: PureXML.Schema.Term) -> [String: PureXML.Schema.ElementType] {
        var result: [String: XSDElementType] = [:]
        collectTypes(term, into: &result)
        return result
    }

    fileprivate static func collectTypes(_ term: XSDTerm, into result: inout [String: XSDElementType]) {
        switch term {
        case let .element(name, type, _):
            if let type { result[key(name)] = type }
        case let .group(group):
            for member in group.particles {
                collectTypes(member.term, into: &result)
            }
        case .wildcard:
            break
        }
    }

    static func key(_ name: PureXML.Model.QualifiedName) -> String {
        "{\(name.namespaceURI ?? "")}\(name.localName)"
    }

    /// Whether two names match by namespace and local name. Used to match an
    /// instance attribute against a declared attribute use, so attributes that
    /// share a local name in different namespaces are kept distinct.
    static func sameName(_ lhs: PureXML.Model.QualifiedName, _ rhs: PureXML.Model.QualifiedName) -> Bool {
        lhs.namespaceURI == rhs.namespaceURI && lhs.localName == rhs.localName
    }

    /// The element's character content, trimmed: used to decide whether an
    /// element-only or empty type wrongly carries significant text (indentation
    /// whitespace between child elements is not significant).
    static func textContent(_ element: PureXML.Model.Element) -> String {
        rawTextContent(element).trimmingXMLWhitespace()
    }

    /// The element's character content verbatim. Simple-content validation uses
    /// this so the type's own `whiteSpace` facet decides normalization: a
    /// `preserve` type (xs:string) keeps leading/trailing whitespace, while a
    /// `collapse` type still trims and collapses through `process`.
    static func rawTextContent(_ element: PureXML.Model.Element) -> String {
        element.children.reduce(into: "") { result, child in
            switch child {
            case let .text(value), let .cdata(value): result += value
            default: break
            }
        }
    }

    /// Whether `complex` is the ur-type `xsd:anyType`: no declared attributes, a
    /// skip attribute wildcard, and mixed content of a single unbounded skip
    /// element wildcard. The ur-type admits any `xsi:type` substitution.
    static func isUrType(_ complex: PureXML.Schema.ComplexType) -> Bool {
        guard complex.attributes.isEmpty,
              complex.attributeWildcard?.processContents == .skip,
              case let .mixed(particle) = complex.content,
              particle.minOccurs == 0, particle.maxOccurs == nil,
              case let .wildcard(wildcard) = particle.term,
              wildcard.processContents == .skip
        else { return false }
        return true
    }

    static func isNamespaceDeclaration(_ attribute: PureXML.Model.Attribute) -> Bool {
        attribute.name.prefix == "xmlns" || (attribute.name.prefix == nil && attribute.name.localName == "xmlns")
    }

    /// Whether an attribute belongs to the XML Schema instance namespace
    /// (`xsi:type`, `xsi:nil`, and the schema-location hints), which are
    /// processing directives rather than declared attributes.
    static func isSchemaInstanceAttribute(_ attribute: PureXML.Model.Attribute) -> Bool {
        attribute.name.namespaceURI == "http://www.w3.org/2001/XMLSchema-instance" || attribute.name.prefix == "xsi"
    }

    /// The local name of an element's `xsi:type` attribute value, or nil when it
    /// carries none. Recognizes the attribute by the XML Schema instance
    /// namespace or, failing namespace resolution, the conventional `xsi` prefix.
    static func xsiTypeName(_ element: PureXML.Model.Element) -> String? {
        let schemaInstance = "http://www.w3.org/2001/XMLSchema-instance"
        let match = element.attributes.first { attribute in
            attribute.name.localName == "type"
                && (attribute.name.namespaceURI == schemaInstance || attribute.name.prefix == "xsi")
        }
        return match.map { $0.value.split(separator: ":").last.map(String.init) ?? $0.value }
    }
}

extension PureXML.Schema.ComplexValidator {
    /// Whether the element carries `xsi:nil="true"`.
    static func isNil(_ element: PureXML.Model.Element) -> Bool {
        element.attributes.contains { attribute in
            attribute.name.localName == "nil"
                && (attribute.name.namespaceURI == "http://www.w3.org/2001/XMLSchema-instance" || attribute.name.prefix == "xsi")
                && attribute.value == "true"
        }
    }

    /// Whether the element has any child element or non-whitespace text.
    static func hasContent(_ element: PureXML.Model.Element) -> Bool {
        !textContent(element).isEmpty || element.children.contains { if case .element = $0 { true } else { false } }
    }
}

public extension PureXML.Schema {
    /// The outcome of following a `typeReference` chain: the underlying simple or
    /// complex type, or the failure to report (an unknown name, or a circular
    /// chain that can never resolve).
    enum TypeResolution {
        case resolved(ElementType)
        case unknown(String)
        case circular(String)
    }
}

extension PureXML.Schema.ComplexValidator {
    /// Follows a `typeReference` chain through `types` with cycle detection, the
    /// one shared resolver behind the tree validator, the streaming validator, and
    /// completions, so unknown names and circular chains are reported identically
    /// everywhere instead of being silently truncated.
    static func resolveReference(
        _ type: PureXML.Schema.ElementType,
        in types: [String: PureXML.Schema.ElementType],
    ) -> PureXML.Schema.TypeResolution {
        var current = type
        var visited: Set<String> = []
        while case let .typeReference(name) = current {
            guard visited.insert(name).inserted else { return .circular(name) }
            guard let next = types[name] else { return .unknown(name) }
            current = next
        }
        return .resolved(current)
    }

    /// The instance resolver over this validator's type table.
    func resolveReference(_ type: PureXML.Schema.ElementType) -> PureXML.Schema.TypeResolution {
        Self.resolveReference(type, in: types)
    }
}
