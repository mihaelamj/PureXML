extension PureXML.Validation.DTD {
    // MARK: Content models

    static func contentViolations(_ element: DTDElement, model: PureXML.Validation.ContentModel, at path: DTDPath) -> [DTDFailure] {
        let name = element.name.description
        let content = childContent(of: element)
        switch model {
        case .empty:
            return content.names.isEmpty && !content.hasText
                ? []
                : [DTDFailure(reason: "element <\(name)> is declared EMPTY but has content", at: path)]
        case .any:
            return []
        case .pcdata:
            return content.names.isEmpty
                ? []
                : [DTDFailure(reason: "element <\(name)> is declared (#PCDATA) but has child elements", at: path)]
        case let .mixed(allowed):
            return content.names
                .filter { !allowed.contains($0) }
                .map { DTDFailure(reason: "element <\($0)> is not allowed in the mixed content of <\(name)>", at: path) }
        case let .children(particle):
            return childrenViolations(name: name, particle: particle, content: content, at: path)
        }
    }

    private static func childrenViolations(
        name: String,
        particle: PureXML.Validation.Particle,
        content: (names: [String], hasText: Bool),
        at path: DTDPath,
    ) -> [DTDFailure] {
        var result: [DTDFailure] = []
        if content.hasText {
            result.append(DTDFailure(reason: "element <\(name)> has element content but contains character data", at: path))
        }
        if !PureXML.Validation.ContentModelMatcher.matchesChildren(particle, content.names) {
            result.append(DTDFailure(reason: "the children of <\(name)> do not match its content model", at: path))
        }
        return result
    }

    private static func childContent(of element: DTDElement) -> (names: [String], hasText: Bool) {
        var names: [String] = []
        var hasText = false
        for child in element.children {
            switch child {
            case let .element(inner):
                names.append(inner.name.description)
            case let .text(value), let .cdata(value):
                if value.contains(where: { !$0.isWhitespace }) { hasText = true }
            default:
                break
            }
        }
        return (names, hasText)
    }

    // MARK: Attributes

    static func attributeViolations(
        _ declaration: PureXML.Validation.AttributeDeclaration,
        on element: DTDElement,
        at path: DTDPath,
    ) -> [DTDFailure] {
        let name = element.name.description
        let value = element.attributes.first {
            $0.name.description == declaration.name || $0.name.localName == declaration.name
        }?.value
        guard let value else {
            return declaration.defaultDecl == .required
                ? [DTDFailure(reason: "required attribute '\(declaration.name)' is missing on <\(name)>", at: path)]
                : []
        }
        var result: [DTDFailure] = []
        if case let .fixed(fixedValue) = declaration.defaultDecl, value != fixedValue {
            result.append(DTDFailure(reason: "attribute '\(declaration.name)' on <\(name)> is #FIXED and must be \"\(fixedValue)\"", at: path))
        }
        if case let .enumeration(allowed) = declaration.type, !allowed.contains(value) {
            result.append(DTDFailure(reason: "attribute '\(declaration.name)' on <\(name)> has a value outside its enumeration", at: path))
        }
        return result
    }

    // MARK: ID / IDREF integrity

    static func identifierErrors(_ node: PureXML.Model.Node, schema: PureXML.Validation.DTDSchema, at path: DTDPath) -> [DTDFailure] {
        var counts: [String: Int] = [:]
        var references: [(value: String, element: String)] = []
        collect(node, schema: schema, counts: &counts, references: &references)

        var errors: [DTDFailure] = []
        for (value, count) in counts where count > 1 {
            errors.append(DTDFailure(reason: "duplicate ID '\(value)' (declared \(count) times)", at: path))
        }
        for reference in references where counts[reference.value] == nil {
            errors.append(DTDFailure(reason: "IDREF '\(reference.value)' on <\(reference.element)> matches no ID", at: path))
        }
        return errors
    }

    private static func collect(
        _ node: PureXML.Model.Node,
        schema: PureXML.Validation.DTDSchema,
        counts: inout [String: Int],
        references: inout [(value: String, element: String)],
    ) {
        switch node {
        case let .document(children):
            for child in children {
                collect(child, schema: schema, counts: &counts, references: &references)
            }
        case let .element(element):
            collectIdentifiers(element, schema: schema, counts: &counts, references: &references)
            for child in element.children {
                collect(child, schema: schema, counts: &counts, references: &references)
            }
        case .text, .cdata, .comment, .processingInstruction:
            break
        }
    }

    private static func collectIdentifiers(
        _ element: DTDElement,
        schema: PureXML.Validation.DTDSchema,
        counts: inout [String: Int],
        references: inout [(value: String, element: String)],
    ) {
        let name = element.name.description
        guard let declarations = schema.attributes[name] else { return }
        for declaration in declarations {
            guard let value = element.attributes.first(where: {
                $0.name.description == declaration.name || $0.name.localName == declaration.name
            })?.value else { continue }
            switch declaration.type {
            case .id:
                counts[value, default: 0] += 1
            case .idReference:
                references.append((value, name))
            case .idReferences:
                for token in value.split(whereSeparator: { $0.isWhitespace }) {
                    references.append((String(token), name))
                }
            case .cdata, .enumeration:
                break
            }
        }
    }
}
