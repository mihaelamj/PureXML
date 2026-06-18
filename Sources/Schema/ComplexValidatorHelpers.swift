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
        case let .element(name, _, _, _, _, _): .name(name)
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
        case let .element(name, type, _, _, _, _):
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

    /// Namespace prefix bindings declared on an element (`xmlns`, `xmlns:p`).
    static func namespaceBindingsDeclared(on element: PureXML.Model.Element) -> [String: String] {
        var bindings: [String: String] = [:]
        for attribute in element.attributes {
            if attribute.name.prefix == "xmlns" {
                bindings[attribute.name.localName] = attribute.value
            } else if attribute.name.prefix == nil, attribute.name.localName == "xmlns" {
                bindings[""] = attribute.value
            }
        }
        return bindings
    }

    /// In-scope prefix bindings for `element`, merging ancestor declarations.
    static func namespaceBindings(for element: PureXML.Model.Element, inherited: [String: String] = [:]) -> [String: String] {
        inherited.merging(namespaceBindingsDeclared(on: element)) { _, new in new }
    }

    /// The lexical `xsi:type` attribute value, when present.
    static func xsiTypeAttributeValue(_ element: PureXML.Model.Element) -> String? {
        let schemaInstance = "http://www.w3.org/2001/XMLSchema-instance"
        let match = element.attributes.first { attribute in
            attribute.name.localName == "type"
                && (attribute.name.namespaceURI == schemaInstance || attribute.name.prefix == "xsi")
        }
        return match?.value.trimmingXMLWhitespace()
    }

    /// Resolves an instance `xsi:type` attribute to a named type-table key.
    static func xsiTypeReference(_ element: PureXML.Model.Element, namespaceBindings: [String: String]) -> String? {
        guard let value = xsiTypeAttributeValue(element) else { return nil }
        let local = value.split(separator: ":").last.map(String.init) ?? value
        if value.contains(":"), let prefix = value.split(separator: ":", maxSplits: 1).first.map(String.init), let uri = namespaceBindings[prefix] {
            return PureXML.Schema.XSDParser.typeDeclarationKey(local, namespaceURI: uri)
        }
        if let uri = namespaceBindings[""] {
            return PureXML.Schema.XSDParser.typeDeclarationKey(local, namespaceURI: uri)
        }
        return local
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
    /// `lax` attribute wildcard, and mixed content of a single unbounded `lax`
    /// element wildcard (XSD 1.0 §3.4.7). The ur-type admits any `xsi:type`
    /// substitution. A `skip` wildcard is also accepted so any legacy construction
    /// of the ur-type still reads as the ur-type.
    static func isUrType(_ complex: PureXML.Schema.ComplexType) -> Bool {
        guard complex.attributes.isEmpty,
              complex.attributeWildcard?.processContents != .strict,
              case let .mixed(particle) = complex.content,
              particle.minOccurs == 0, particle.maxOccurs == nil,
              case let .wildcard(wildcard) = particle.term,
              wildcard.processContents != .strict
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
        xsiTypeAttributeValue(element).map { $0.split(separator: ":").last.map(String.init) ?? $0 }
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
            guard let next = resolveNamedType(name, in: types) else { return .unknown(name) }
            current = next
        }
        return .resolved(current)
    }

    /// Resolves a named type reference, including built-in datatypes and ur-types.
    static func resolveNamedType(_ name: String, in types: [String: PureXML.Schema.ElementType]) -> PureXML.Schema.ElementType? {
        if let next = types[name] { return next }
        if name.hasPrefix("type:"), let (uri, local) = parseQualifiedTypeKey(name) {
            if uri == PureXML.Schema.XSDParser.xsdNamespace, let builtin = urOrBuiltinType(named: local) {
                return builtin
            }
            if let next = types[PureXML.Schema.XSDParser.typeDeclarationKey(local, namespaceURI: uri)] {
                return next
            }
        }
        if !name.hasPrefix("type:"), let next = types[PureXML.Schema.XSDParser.typeDeclarationKey(name, namespaceURI: nil)] {
            return next
        }
        if let builtin = PureXML.Schema.BuiltinType(rawValue: name) {
            return .simple(PureXML.Schema.SimpleType(base: builtin))
        }
        if name == "anySimpleType" {
            return .simple(PureXML.Schema.SimpleType(base: .string, isAnySimpleType: true))
        }
        if name == "anyType" {
            return .complex(Self.urComplexType)
        }
        if let item = PureXML.Schema.XSDSimpleParser.listBuiltinItem(name) {
            return .simple(.list(item: PureXML.Schema.SimpleType(base: item), isBuiltinList: true))
        }
        return nil
    }

    private static func parseQualifiedTypeKey(_ name: String) -> (uri: String, local: String)? {
        let keyBody = String(name.dropFirst("type:".count))
        guard keyBody.hasPrefix("{"), let close = keyBody.firstIndex(of: "}") else { return nil }
        let uri = String(keyBody[keyBody.index(after: keyBody.startIndex) ..< close])
        let local = String(keyBody[keyBody.index(after: close)...])
        return (uri, local)
    }

    private static func urOrBuiltinType(named local: String) -> PureXML.Schema.ElementType? {
        if let builtin = PureXML.Schema.BuiltinType(rawValue: local) {
            return .simple(PureXML.Schema.SimpleType(base: builtin))
        }
        if local == "anySimpleType" {
            return .simple(PureXML.Schema.SimpleType(base: .string, isAnySimpleType: true))
        }
        if local == "anyType" {
            return .complex(urComplexType)
        }
        return nil
    }

    /// The ur-type `xsd:anyType`. Per XSD 1.0 §3.4.7 its element and attribute
    /// wildcards are `lax` (not skip): declared children and attributes are
    /// validated against their global declarations, undeclared content is admitted.
    static let urComplexType = PureXML.Schema.ComplexType(
        attributeWildcard: PureXML.Schema.Wildcard(processContents: .lax),
        content: .mixed(PureXML.Schema.Particle(
            minOccurs: 0,
            maxOccurs: nil,
            term: .wildcard(PureXML.Schema.Wildcard(processContents: .lax)),
        )),
    )

    /// The instance resolver over this validator's type table.
    func resolveReference(_ type: PureXML.Schema.ElementType) -> PureXML.Schema.TypeResolution {
        Self.resolveReference(type, in: types)
    }
}
