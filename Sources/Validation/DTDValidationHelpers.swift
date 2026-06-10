extension PureXML.Validation.DTD {
    // MARK: Content models

    static func contentViolations(_ element: DTDElement, model: PureXML.Validation.ContentModel, at path: DTDPath) -> [DTDFailure] {
        let name = element.name.description
        let content = childContent(of: element)
        switch model {
        case .empty:
            return content.names.isEmpty && !content.hasText && !content.hasCDATA
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
        content: ChildContent,
        at path: DTDPath,
    ) -> [DTDFailure] {
        var result: [DTDFailure] = []
        if content.hasText || content.hasCDATA {
            // A CDATA section is character data in element content even when
            // empty or whitespace-only.
            result.append(DTDFailure(reason: "element <\(name)> has element content but contains character data", at: path))
        }
        guard !PureXML.Validation.ContentModelMatcher.matchesChildren(particle, content.names) else { return result }
        // Name each child outside the model's alphabet; if every child is in the
        // alphabet the fault is order or count, so report it once with the allowed
        // elements as a recovery hint.
        let allowed = PureXML.Validation.ContentModelMatcher.allowedNames(particle)
        let stray = content.names.filter { !allowed.contains($0) }
        if stray.isEmpty {
            let hint = allowed.sorted().map { "<\($0)>" }.joined(separator: ", ")
            result.append(DTDFailure(reason: "the children of <\(name)> do not match its content model; allowed: \(hint)", at: path))
        } else {
            for child in orderedUnique(stray) {
                result.append(DTDFailure(reason: "element <\(child)> is not allowed in <\(name)>", at: path))
            }
        }
        return result
    }

    /// The distinct values of `names`, in first-seen order.
    private static func orderedUnique(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.filter { seen.insert($0).inserted }
    }

    /// One element's immediate content, summarized for model matching.
    struct ChildContent {
        var names: [String] = []
        var hasText = false
        /// Present CDATA sections, which count as character data in element
        /// content even when empty or whitespace-only.
        var hasCDATA = false
    }

    private static func childContent(of element: DTDElement) -> ChildContent {
        var content = ChildContent()
        for child in element.children {
            switch child {
            case let .element(inner):
                content.names.append(inner.name.description)
            case let .text(value):
                if value.contains(where: { !$0.isWhitespace }) { content.hasText = true }
            case .cdata:
                content.hasCDATA = true
            default:
                break
            }
        }
        return content
    }

    // MARK: Attributes

    /// The value supplied for a declaration's attribute on an element, or nil
    /// when it is absent, normalized per its declared type: for any non-CDATA
    /// type, whitespace runs collapse to a single space and leading/trailing
    /// whitespace is stripped (3.3.3), so ` nonce ` satisfies an enumeration
    /// listing `nonce` and an IDREF resolves regardless of surrounding space.
    static func attributeValue(of declaration: PureXML.Validation.AttributeDeclaration, on element: DTDElement) -> String? {
        let raw = element.attributes.first {
            $0.name.description == declaration.name || $0.name.localName == declaration.name
        }?.value
        return raw.map { normalize($0, for: declaration.type) }
    }

    /// The 3.3.3 tokenized normalization. CDATA values pass through untouched.
    static func normalize(_ value: String, for type: PureXML.Validation.AttributeType) -> String {
        if case .cdata = type { return value }
        return value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The error when a `#REQUIRED` attribute is absent.
    static func requiredViolation(_ declaration: PureXML.Validation.AttributeDeclaration, on element: DTDElement, at path: DTDPath) -> DTDFailure? {
        guard declaration.defaultDecl == .required, attributeValue(of: declaration, on: element) == nil else { return nil }
        return DTDFailure(reason: "required attribute '\(declaration.name)' is missing on <\(element.name.description)>", at: path)
    }

    /// The error when a `#FIXED` attribute is present with a value other than the
    /// fixed one.
    static func fixedViolation(_ declaration: PureXML.Validation.AttributeDeclaration, on element: DTDElement, at path: DTDPath) -> DTDFailure? {
        guard case let .fixed(fixedValue) = declaration.defaultDecl,
              let value = attributeValue(of: declaration, on: element), value != fixedValue else { return nil }
        return DTDFailure(reason: "attribute '\(declaration.name)' on <\(element.name.description)> is #FIXED and must be \"\(fixedValue)\"", at: path)
    }

    /// The error when an enumerated attribute is present with a value outside its
    /// list.
    static func enumerationViolation(_ declaration: PureXML.Validation.AttributeDeclaration, on element: DTDElement, at path: DTDPath) -> DTDFailure? {
        guard case let .enumeration(allowed) = declaration.type,
              let value = attributeValue(of: declaration, on: element), !allowed.contains(value) else { return nil }
        return DTDFailure(reason: "attribute '\(declaration.name)' on <\(element.name.description)> has a value outside its enumeration", at: path)
    }

    /// The error when a `NOTATION` attribute value is not one of the names its
    /// declaration lists, or names a notation that is not declared with
    /// `<!NOTATION>`. Returns nil for any other attribute type.
    static func notationError(
        _ declaration: PureXML.Validation.AttributeDeclaration,
        value: String,
        on element: String,
        notations: Set<String>,
        at path: DTDPath,
    ) -> DTDFailure? {
        guard case let .notation(allowed) = declaration.type else { return nil }
        if !allowed.contains(value) {
            return DTDFailure(reason: "attribute '\(declaration.name)' on <\(element)> has a value outside its NOTATION list", at: path)
        }
        if !notations.contains(value) {
            return DTDFailure(reason: "attribute '\(declaration.name)' on <\(element)> names undeclared notation '\(value)'", at: path)
        }
        return nil
    }

    /// The error when a tokenized attribute value does not match its declared
    /// lexical form: `NMTOKEN(S)` must be name token(s), and `ENTITY`/`ENTITIES`
    /// must name declared unparsed (`NDATA`) entities. The ID family is checked
    /// separately for cross-reference integrity.
    static func tokenizedTypeError(
        _ declaration: PureXML.Validation.AttributeDeclaration,
        value: String,
        on element: String,
        entities: Set<String>,
        at path: DTDPath,
    ) -> DTDFailure? {
        let isNmtoken = PureXML.Parsing.XMLCharacter.isNmtoken
        let isName = PureXML.Parsing.XMLCharacter.isValidName
        let isEntity = { (token: String) in isName(token) && entities.contains(token) }
        let tokens = value.split(whereSeparator: \.isWhitespace).map(String.init)
        let valid: Bool
        switch declaration.type {
        case .nmToken: valid = isNmtoken(value)
        case .nmTokens: valid = !tokens.isEmpty && tokens.allSatisfy(isNmtoken)
        case .entity: valid = isEntity(value)
        case .entities: valid = !tokens.isEmpty && tokens.allSatisfy(isEntity)
        // The ID family must be lexical Names (VC: ID, IDREF); uniqueness and
        // resolution are checked by the whole-tree integrity rule.
        case .id, .idReference: valid = isName(value)
        case .idReferences: valid = !tokens.isEmpty && tokens.allSatisfy(isName)
        case .cdata, .enumeration, .notation: return nil
        }
        guard !valid else { return nil }
        return DTDFailure(reason: "attribute '\(declaration.name)' on <\(element)> is not a valid \(typeName(declaration.type))", at: path)
    }

    private static func typeName(_ type: PureXML.Validation.AttributeType) -> String {
        switch type {
        case .nmToken: "NMTOKEN"
        case .nmTokens: "NMTOKENS"
        case .entity: "ENTITY"
        case .entities: "ENTITIES"
        case .id: "ID"
        case .idReference: "IDREF"
        case .idReferences: "IDREFS"
        default: "value"
        }
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
            guard let value = attributeValue(of: declaration, on: element) else { continue }
            switch declaration.type {
            case .id:
                counts[value, default: 0] += 1
            case .idReference:
                references.append((value, name))
            case .idReferences:
                for token in value.split(whereSeparator: { $0.isWhitespace }) {
                    references.append((String(token), name))
                }
            case .cdata, .enumeration, .notation, .nmToken, .nmTokens, .entity, .entities:
                break
            }
        }
    }
}
