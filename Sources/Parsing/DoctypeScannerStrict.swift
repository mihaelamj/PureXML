/// The strict XML 1.0 grammar for `<!ENTITY>` declarations, external
/// identifiers, and public-identifier literals, split from the scanner body to
/// keep it under the length caps. The scan is one well-formedness gate: any
/// deviation throws a located `ParseError`.
extension DTDScanner {
    mutating func scanEntityDeclaration(_ reader: inout Reader) throws {
        let mark = reader.mark
        reader.consume("<!ENTITY")
        guard reader.peek()?.isWhitespace == true else {
            throw ParseError.invalidEntityDeclaration(mark)
        }
        reader.skipSpace()
        let isParameter = reader.consume("%")
        if isParameter {
            guard reader.peek()?.isWhitespace == true else {
                throw ParseError.invalidEntityDeclaration(mark)
            }
            reader.skipSpace()
        }
        let name = scanName(&reader)
        guard !name.isEmpty else {
            throw ParseError.invalidEntityDeclaration(mark)
        }
        guard reader.peek()?.isWhitespace == true else {
            throw ParseError.invalidEntityDeclaration(mark)
        }
        reader.skipSpace()
        if let value = scanLiteral(&reader) {
            try scanInternalEntityTail(&reader, name: name, value: value, isParameter: isParameter, at: mark)
            return
        }
        try scanExternalEntityTail(&reader, name: name, isParameter: isParameter, at: mark)
    }

    /// The tail of an internal entity: the literal already read, then `S? '>'`.
    private mutating func scanInternalEntityTail(_ reader: inout Reader, name: String, value: String, isParameter: Bool, at mark: Mark) throws {
        try validateEntityLiteral(value, at: mark)
        reader.skipSpace()
        guard reader.peek() == ">" else {
            throw ParseError.invalidEntityDeclaration(mark)
        }
        skip(&reader, until: ">")
        storeEntity(name: name, value: expandParameterReferences(value), isParameter: isParameter)
    }

    /// The tail of an external entity: the identifier, an optional `S NDATA Name`
    /// (general entities only), then `S? '>'`.
    private mutating func scanExternalEntityTail(_ reader: inout Reader, name: String, isParameter: Bool, at mark: Mark) throws {
        guard let id = try parseStrictExternalID(&reader, requireSystem: true, at: mark) else {
            throw ParseError.invalidEntityDeclaration(mark)
        }
        var notation: String?
        if reader.peek()?.isWhitespace == true {
            reader.skipSpace()
            if reader.consume("NDATA") {
                // NDATA is for unparsed general entities only.
                guard !isParameter else {
                    throw ParseError.invalidEntityDeclaration(mark)
                }
                notation = notationName(&reader)
            }
        } else if reader.peek() != ">" {
            throw ParseError.invalidEntityDeclaration(mark)
        }
        reader.skipSpace()
        guard reader.peek() == ">" else {
            throw ParseError.invalidEntityDeclaration(mark)
        }
        skip(&reader, until: ">")
        storeExternalEntity(name: name, id: id, isParameter: isParameter, notation: notation)
    }

    /// Validates an entity value literal: every character must be an XML Char,
    /// and every `&` must begin a complete reference (`&name;` or a character
    /// reference); a bare ampersand is not well-formed.
    func validateEntityLiteral(_ value: String, at mark: Mark) throws {
        let characters = Array(value)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard character.unicodeScalars.allSatisfy(PureXML.Parsing.XMLCharacter.isChar) else {
                throw ParseError.invalidCharacter(mark)
            }
            if character == "&" {
                var probe = index + 1
                if probe < characters.count, characters[probe] == "#" { probe += 1 }
                let bodyStart = probe
                while probe < characters.count, characters[probe] != ";", !characters[probe].isWhitespace, characters[probe] != "&" {
                    probe += 1
                }
                guard probe > bodyStart, probe < characters.count, characters[probe] == ";" else {
                    throw ParseError.invalidReference("&", mark)
                }
                index = probe
            }
            index += 1
        }
    }

    /// Parses an external identifier strictly: `SYSTEM S literal`, or
    /// `PUBLIC S pubid-literal S system-literal` (the system literal is required
    /// when `requireSystem` is true, as for entities and the DOCTYPE itself).
    /// Public identifiers are checked against the `PubidChar` set.
    func parseStrictExternalID(_ reader: inout Reader, requireSystem: Bool, at mark: Mark) throws -> ExternalID? {
        if reader.consume("SYSTEM") {
            guard reader.peek()?.isWhitespace == true else {
                throw ParseError.invalidEntityDeclaration(mark)
            }
            reader.skipSpace()
            guard let systemID = scanLiteral(&reader) else {
                throw ParseError.invalidEntityDeclaration(mark)
            }
            return ExternalID(systemID: systemID)
        }
        if reader.consume("PUBLIC") {
            return try parsePublicID(&reader, requireSystem: requireSystem, at: mark)
        }
        return nil
    }

    /// `PUBLIC S PubidLiteral (S SystemLiteral)` with the system literal
    /// required for entities and the DOCTYPE, optional for notations.
    private func parsePublicID(_ reader: inout Reader, requireSystem: Bool, at mark: Mark) throws -> ExternalID {
        guard reader.peek()?.isWhitespace == true else {
            throw ParseError.invalidEntityDeclaration(mark)
        }
        reader.skipSpace()
        guard let publicID = scanLiteral(&reader) else {
            throw ParseError.invalidEntityDeclaration(mark)
        }
        try validatePublicID(publicID, at: mark)
        if requireSystem {
            guard reader.peek()?.isWhitespace == true else {
                throw ParseError.invalidEntityDeclaration(mark)
            }
            reader.skipSpace()
            guard let systemID = scanLiteral(&reader) else {
                throw ParseError.invalidEntityDeclaration(mark)
            }
            return ExternalID(publicID: publicID, systemID: systemID)
        }
        // Notations may carry a public identifier alone.
        var systemID = ""
        if reader.peek()?.isWhitespace == true {
            reader.skipSpace()
            if let literal = scanLiteral(&reader) { systemID = literal }
        }
        return ExternalID(publicID: publicID, systemID: systemID)
    }

    /// `PubidChar ::= #x20 | #xD | #xA | [a-zA-Z0-9] | [-'()+,./:=?;!*#@$_%]`
    func validatePublicID(_ publicID: String, at mark: Mark) throws {
        let allowed = Set("-'()+,./:=?;!*#@$_%")
        for character in publicID {
            let valid = character == " " || character == "\r" || character == "\n"
                || (character.isASCII && (character.isLetter || character.isNumber))
                || allowed.contains(character)
            guard valid else {
                throw ParseError.invalidPublicIdentifier(mark)
            }
        }
    }
}
