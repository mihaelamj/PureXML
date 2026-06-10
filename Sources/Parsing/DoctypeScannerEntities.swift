/// The entity side of the DTD scan: storing declarations, resolving external
/// entities through the injected resolver, expanding parameter-entity
/// references, and the bare `%name;` declaration-stream injection. Split from
/// the scanner body to keep it under the length caps.
extension DTDScanner {
    /// Folds declared external general entities into the general-entity table by
    /// asking the resolver for their replacement text. A refused (nil) entity
    /// stays undeclared, so a reference to it errors and the default refusing
    /// resolver keeps XXE closed.
    mutating func resolveExternalEntities() {
        for (name, id) in doctype.externalEntities where doctype.entities[name] == nil {
            if let text = resolver.resolveEntity(name, baseResolved(id)) {
                // An external parsed entity may begin with a text declaration,
                // which is not part of its replacement text (4.3.1).
                doctype.entities[name] = try? strippingTextDeclaration(text)
            }
        }
    }

    /// The identifier with its base applied into the system ID, so a resolver
    /// that only reads `systemID` still sees the resolved path.
    func baseResolved(_ id: ExternalID) -> ExternalID {
        var resolved = id
        resolved.systemID = id.resolvedSystemID
        resolved.base = nil
        return resolved
    }

    /// Handles a bare `%name;` between declarations by injecting the parameter
    /// entity's replacement text and scanning its declarations. Bounded by depth
    /// and the expansion budget.
    mutating func scanParameterReference(_ reader: inout Reader, depth: Int, at mark: Mark) throws {
        let refMark = reader.mark
        reader.consume("%")
        let name = scanName(&reader)
        // PEReference is '%' Name ';' exactly: no space after '%' (an empty
        // name) and the semicolon must follow the name directly.
        guard !name.isEmpty, reader.consume(";") else {
            throw ParseError.invalidReference("%\(name)", refMark)
        }
        guard let replacement = doctype.parameterEntities[name] else {
            // A declared external PE the resolver refused is not undeclared,
            // the processor just did not read it.
            guard !unresolvedParameterEntities.contains(name) else { return }
            // VC/WFC: Entity Declared (also covers a reference before the
            // declaration: declarations bind in document order).
            if entityDeclaredIsWellFormedness {
                throw ParseError.undefinedEntity(name: name, refMark)
            }
            doctype.validityFindings.append("parameter entity '%\(name);' is referenced but not declared")
            return
        }
        guard depth < maxDepth else {
            return
        }
        guard parameterBudget >= replacement.count else {
            return
        }
        parameterBudget -= replacement.count
        var sub = Reader(replacement)
        // Identifiers declared inside the replacement resolve against the
        // parameter entity's own URI (per-entity base, RFC 3986).
        let outerBase = currentBase
        if let base = parameterEntityBases[name] {
            currentBase = base
        }
        defer { currentBase = outerBase }
        try scanDeclarations(&sub, depth: depth + 1, terminatedByBracket: false, at: mark)
    }

    /// Files an external entity declaration by kind: an `NDATA` entity is unparsed
    /// (recorded with its notation); an external general entity records its
    /// identifier for the resolver; an external parameter entity is loaded through
    /// the resolver so its replacement text is available for `%name;` expansion
    /// (the default refusing resolver loads nothing, keeping XXE closed).
    mutating func storeExternalEntity(name: String, id: ExternalID, isParameter: Bool, notation: String?) {
        if let notation, !notation.isEmpty, !isParameter {
            if doctype.unparsedEntities[name] == nil {
                doctype.unparsedEntities[name] = PureXML.Parsing.UnparsedEntity(id: id, notation: notation)
            }
        } else if isParameter {
            if doctype.parameterEntities[name] == nil {
                if let text = resolver.resolveExternalSubset(baseResolved(id)) {
                    if let stripped = try? strippingTextDeclaration(text) {
                        doctype.parameterEntities[name] = expandParameterReferences(stripped)
                        parameterEntityBases[name] = id.resolvedSystemID
                    } else {
                        unresolvedParameterEntities.insert(name)
                    }
                } else {
                    unresolvedParameterEntities.insert(name)
                }
            }
        } else if doctype.externalEntities[name] == nil {
            doctype.externalEntities[name] = id
        }
    }

    /// `<!NOTATION S Name S (ExternalID | PublicID) S? '>'` (production 82):
    /// the identifier is required and nothing may follow it but whitespace.
    /// Replaces `%name;` references with their (already-expanded) parameter-entity
    /// values. Undefined references are left literal. A single forward pass is
    /// enough because each value was expanded against the entities defined before
    /// it, so no reference can reach a later definition.
    func expandParameterReferences(_ raw: String) -> String {
        guard raw.contains("%") else { return raw }
        var result = ""
        var index = raw.startIndex
        while index < raw.endIndex {
            let character = raw[index]
            guard character == "%", let semicolon = raw[index...].firstIndex(of: ";") else {
                result.append(character)
                index = raw.index(after: index)
                continue
            }
            let name = String(raw[raw.index(after: index) ..< semicolon])
            result += doctype.parameterEntities[name] ?? "%\(name);"
            index = raw.index(after: semicolon)
        }
        return result
    }
}
