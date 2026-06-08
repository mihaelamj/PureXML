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
        case let .element(name, _): .name(name)
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

    static func key(_ name: PureXML.Model.QualifiedName) -> String {
        "{\(name.namespaceURI ?? "")}\(name.localName)"
    }

    /// Whether two names match by namespace and local name. Used to match an
    /// instance attribute against a declared attribute use, so attributes that
    /// share a local name in different namespaces are kept distinct.
    static func sameName(_ lhs: PureXML.Model.QualifiedName, _ rhs: PureXML.Model.QualifiedName) -> Bool {
        lhs.namespaceURI == rhs.namespaceURI && lhs.localName == rhs.localName
    }

    static func textContent(_ element: PureXML.Model.Element) -> String {
        let text = element.children.reduce(into: "") { result, child in
            switch child {
            case let .text(value), let .cdata(value): result += value
            default: break
            }
        }
        return text.trimmingXMLWhitespace()
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
