/// The validity-aware side of reference handling: which entities a reference
/// may see (the standalone WFC), whether an undeclared reference is fatal
/// (production 68), and the errata E15 content findings. Split from the
/// reader body to keep it under the length caps.
extension PureXML.Parsing.EventReader {
    typealias EntityDecoder = PureXML.Parsing.EntityDecoder
    typealias Mark = PureXML.Parsing.Mark

    /// The entity table visible to references. A standalone document must
    /// not reference an entity declared outside its internal subset (WFC:
    /// Entity Declared, 2.9), so external declarations are hidden and such
    /// a reference reports as undeclared.
    var referencableEntities: [String: String] {
        guard xmlDeclaration?.standalone == true else { return documentType.entities }
        return documentType.entities.filter { documentType.internalEntities.contains($0.key) }
    }

    /// Whether an undeclared entity reference is fatal (production 68):
    /// it is a WFC when the document is standalone or could not have
    /// external declarations, and a validity finding otherwise.
    var undeclaredEntityIsFatal: Bool {
        if xmlDeclaration?.standalone == true { return true }
        return documentType.externalSubset == nil && documentType.parameterEntities.isEmpty
    }

    /// Decodes references in text or an attribute value, with undeclared
    /// entities routed per `undeclaredEntityIsFatal`.
    mutating func decodeReferences(_ raw: String, at mark: Mark) throws -> String {
        guard undeclaredEntityIsFatal else {
            var undeclared: [String] = []
            let decoded = try EntityDecoder.decodeLenient(
                raw,
                entities: referencableEntities,
                budget: &entityBudget,
                at: mark,
                undeclared: &undeclared,
            )
            for name in undeclared {
                documentType.validityFindings.append(PureXML.Parsing.ValidityFinding("general entity '&\(name);' is referenced but not declared"))
            }
            return decoded
        }
        return try EntityDecoder.decode(raw, entities: referencableEntities, budget: &entityBudget, at: mark)
    }

    /// Whether the run contains a direct character reference, or references
    /// an entity whose stored replacement does (the errata E15h shape: the
    /// double-escaped reference surfaces when the replacement is reparsed).
    mutating func referencesCharacter(_ raw: String) -> Bool {
        if containsCharacterReference(raw) { return true }
        let entities = referencableEntities
        var index = raw.startIndex
        while index < raw.endIndex, let amp = raw[index...].firstIndex(of: "&") {
            guard let semicolon = raw[amp...].firstIndex(of: ";") else { return false }
            let name = String(raw[raw.index(after: amp) ..< semicolon])
            if let replacement = entities[name], containsCharacterReference(replacement) {
                return true
            }
            index = raw.index(after: semicolon)
        }
        return false
    }

    /// Whether the text contains a direct character reference (Foundation-
    /// free substring test).
    func containsCharacterReference(_ raw: String) -> Bool {
        var sawAmp = false
        for character in raw {
            if sawAmp, character == "#" { return true }
            sawAmp = character == "&"
        }
        return false
    }

    /// Records the errata E15 finding for non-element content inside an
    /// element declared EMPTY.
    mutating func recordEmptyElementContent(_ what: String) {
        guard let current = open.last,
              let model = documentType.elementModels[current.localName] ?? documentType.elementModels[current.description],
              model == "EMPTY"
        else { return }
        documentType.validityFindings.append(PureXML.Parsing.ValidityFinding(
            "\(what) appears in the EMPTY element <\(current.description)>",
            subject: current.description,
        ))
    }

    /// The errata E15 validity findings a text run can carry: any reference
    /// inside an element declared EMPTY, and reference-derived whitespace
    /// (which is character data, not ignorable whitespace) inside element
    /// content.
    mutating func recordReferenceContentFindings(raw: String, decoded: String) {
        guard raw.contains("&"), let current = open.last,
              let model = documentType.elementModels[current.localName] ?? documentType.elementModels[current.description]
        else { return }
        if model == "EMPTY" {
            documentType.validityFindings.append(PureXML.Parsing.ValidityFinding(
                "a reference appears in the EMPTY element <\(current.description)>",
                subject: current.description,
            ))
            return
        }
        // Errata E15: a direct character reference is character data even
        // when it names whitespace; an entity reference whose replacement is
        // whitespace is permitted in element content.
        let isElementContent = model.hasPrefix("(") && !model.hasPrefix("(#PCDATA")
        let isReferenceWhitespace = !decoded.isEmpty && decoded.allSatisfy(\.isWhitespace)
        if isElementContent, isReferenceWhitespace, referencesCharacter(raw) {
            documentType.validityFindings.append(PureXML.Parsing.ValidityFinding(
                "character-reference whitespace in the element content of <\(current.description)>",
                subject: current.description,
            ))
        }
    }

    /// Applies the DTD-declared tokenized normalization to namespace
    /// declaration values before they bind: an `xmlns:b` declared NMTOKEN in
    /// the DTD binds its collapsed value, so ' urn:x ' and 'urn:x' are the
    /// same namespace name (eduni ns 1.0/012).
    mutating func normalizedBindings(
        element: PureXML.Model.QualifiedName,
        attributes: [PureXML.Model.Attribute],
    ) -> [PureXML.Model.Attribute] {
        let hasBinding = attributes.contains { $0.name.prefix == "xmlns" || ($0.name.prefix == nil && $0.name.localName == "xmlns") }
        guard hasBinding,
              let body = documentType.attributeLists[element.description] ?? documentType.attributeLists[element.localName]
        else { return attributes }
        let declarations = PureXML.Validation.AttributeListParser.parse(body)
        return attributes.map { attribute in
            let isBinding = attribute.name.prefix == "xmlns" || (attribute.name.prefix == nil && attribute.name.localName == "xmlns")
            guard isBinding,
                  let declaration = declarations.first(where: { $0.name == attribute.name.description })
            else { return attribute }
            if case .cdata = declaration.type { return attribute }
            let collapsed = attribute.value.split(separator: " ").joined(separator: " ")
            return PureXML.Model.Attribute(name: attribute.name, value: collapsed)
        }
    }
}
