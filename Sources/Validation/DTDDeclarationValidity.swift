extension PureXML.Validation.DTDSchema {
    /// The declaration-level validity constraints: violations that exist in the
    /// DTD itself, independent of any instance content. Computed once when the
    /// schema is built and reported at the document root.
    typealias Finding = PureXML.Validation.ValidationError
    typealias Key = PureXML.Validation.PathKey

    static func declarationFindings(
        _ documentType: PureXML.Parsing.DocumentType,
        attributes: [String: [PureXML.Validation.AttributeDeclaration]],
        notations: Set<String>,
    ) -> [Finding] {
        var findings: [Finding] = []
        // VC: Unique Element Type Declaration.
        for name in documentType.duplicateElements.sorted() {
            findings.append(Finding(reason: "element type '\(name)' is declared more than once", at: [.element(name)]))
        }
        // VC: Notation Declared, an unparsed entity's notation must exist.
        for (entity, unparsed) in documentType.unparsedEntities.sorted(by: { $0.key < $1.key }) {
            guard !notations.contains(unparsed.notation) else { continue }
            findings.append(Finding(
                reason: "unparsed entity '\(entity)' names undeclared notation '\(unparsed.notation)'",
                at: [.element(entity)],
            ))
        }
        // VC: No Duplicate Types in mixed content.
        for (name, model) in documentType.elementModels.sorted(by: { $0.key < $1.key }) {
            if let duplicate = duplicateMixedName(model) {
                findings.append(Finding(reason: "mixed content of '\(name)' repeats '\(duplicate)'", at: [.element(name)]))
            }
        }
        for (element, declarations) in attributes.sorted(by: { $0.key < $1.key }) {
            findings += attributeFindings(element: element, declarations: declarations, notations: notations)
        }
        return findings
    }

    /// One element's attribute-declaration findings: at most one ID attribute,
    /// NOTATION lists name declared notations, and defaults are legal.
    private static func attributeFindings(
        element: String,
        declarations: [PureXML.Validation.AttributeDeclaration],
        notations: Set<String>,
    ) -> [Finding] {
        var findings: [Finding] = []
        if declarations.count(where: { $0.type == .id }) > 1 {
            findings.append(Finding(reason: "element '\(element)' declares more than one ID attribute", at: [.element(element)]))
        }
        for declaration in declarations {
            let path: [Key] = [.element(element), .attribute(declaration.name)]
            if case let .notation(allowed) = declaration.type {
                for name in allowed.sorted() where !notations.contains(name) {
                    findings.append(Finding(
                        reason: "NOTATION attribute '\(declaration.name)' on '\(element)' lists undeclared notation '\(name)'",
                        at: path,
                    ))
                }
            }
            // Errata E2: tokens in an enumerated or NOTATION list must be
            // distinct.
            if let duplicate = duplicateToken(declaration.type) {
                findings.append(Finding(reason: "attribute '\(declaration.name)' on '\(element)' repeats the token '\(duplicate)'", at: path))
            }
            if let problem = defaultProblem(declaration) {
                findings.append(Finding(reason: "attribute '\(declaration.name)' on '\(element)' \(problem)", at: path))
            }
        }
        return findings
    }

    /// The first repeated token of an enumerated or NOTATION type, or nil.
    private static func duplicateToken(_ type: PureXML.Validation.AttributeType) -> String? {
        let tokens: [String]
        switch type {
        case let .enumeration(allowed), let .notation(allowed): tokens = allowed
        default: return nil
        }
        var seen: Set<String> = []
        for token in tokens where !seen.insert(token).inserted {
            return token
        }
        return nil
    }

    /// The first repeated name in a `(#PCDATA|a|b)` mixed model, or nil.
    private static func duplicateMixedName(_ model: String) -> String? {
        let text = model.trimmingXMLWhitespace()
        guard text.hasPrefix("(#PCDATA") else { return nil }
        let inner = text.dropFirst().prefix { $0 != ")" }
        var seen: Set<String> = []
        for token in inner.split(separator: "|").dropFirst() {
            let name = token.trimmingXMLWhitespace()
            if !seen.insert(name).inserted {
                return name
            }
        }
        return nil
    }

    /// Why a declaration's default value is illegal for its type, or nil.
    private static func defaultProblem(_ declaration: PureXML.Validation.AttributeDeclaration) -> String? {
        let defaultValue: String? = switch declaration.defaultDecl {
        case let .fixed(value), let .value(value): value
        case .required, .implied: nil
        }
        // VC: ID Attribute Default, an ID attribute must be #IMPLIED or #REQUIRED.
        if declaration.type == .id {
            return defaultValue == nil ? nil : "is an ID and must be #IMPLIED or #REQUIRED"
        }
        guard let value = defaultValue else { return nil }
        switch declaration.type {
        case let .enumeration(allowed) where !allowed.contains(value):
            return "has a default outside its enumeration"
        case let .notation(allowed) where !allowed.contains(value):
            return "has a default outside its NOTATION list"
        default:
            return tokenizedDefaultProblem(declaration.type, value: value)
        }
    }

    /// The lexical-form problems of a tokenized type's default value.
    private static func tokenizedDefaultProblem(_ type: PureXML.Validation.AttributeType, value: String) -> String? {
        let isName = PureXML.Parsing.XMLCharacter.isValidName
        let isNmtoken = PureXML.Parsing.XMLCharacter.isNmtoken
        let tokens = value.split(whereSeparator: \.isWhitespace).map(String.init)
        switch type {
        case .idReference where !isName(value):
            return "has an IDREF default that is not a Name"
        case .idReferences where tokens.isEmpty || !tokens.allSatisfy(isName):
            return "has an IDREFS default that is not Names"
        case .nmToken where !isNmtoken(value):
            return "has an NMTOKEN default that is not a name token"
        case .nmTokens where tokens.isEmpty || !tokens.allSatisfy(isNmtoken):
            return "has an NMTOKENS default that is not name tokens"
        case .entity where !isName(value):
            return "has an ENTITY default that is not a Name"
        case .entities where tokens.isEmpty || !tokens.allSatisfy(isName):
            return "has an ENTITIES default that is not Names"
        default:
            return nil
        }
    }
}
