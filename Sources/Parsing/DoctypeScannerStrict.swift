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
        let name = try scanStrictName(&reader, at: mark)
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
        // Character references in an entity literal are expanded when the
        // declaration is parsed (4.4.5): `&#37;zz;` stores a usable `%zz;`,
        // `&#60;foo>` stores markup that content splicing reparses, and the
        // Appendix D double escape `&#38;#38;` stores `&#38;`, which the
        // content reparse turns into a literal ampersand. The replacement-text
        // well-formedness constraint still binds at reference time (an
        // unreferenced entity may carry a bad value).
        guard let replacement = PureXML.Parsing.EntityReplacementGrammar.expandCharacterReferences(value) else {
            throw ParseError.invalidEntityDeclaration(mark)
        }
        storeEntity(name: name, value: expandParameterReferences(replacement), isParameter: isParameter)
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
                // NDATA is for unparsed general entities only, and `S Name`
                // must follow (production 76).
                guard !isParameter, reader.peek()?.isWhitespace == true else {
                    throw ParseError.invalidEntityDeclaration(mark)
                }
                reader.skipSpace()
                notation = try scanStrictName(&reader, at: mark)
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
    /// every `&` must begin a complete reference (`&name;` or a character
    /// reference), and every `%` must begin a complete parameter-entity
    /// reference (production 9 admits no bare `%` or `&` in an EntityValue).
    func validateEntityLiteral(_ value: String, at mark: Mark) throws {
        let characters = Array(value)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard character.unicodeScalars.allSatisfy(PureXML.Parsing.XMLCharacter.isChar) else {
                throw ParseError.invalidCharacter(mark)
            }
            if character == "&" || character == "%" {
                var probe = index + 1
                if character == "&", probe < characters.count, characters[probe] == "#" { probe += 1 }
                let bodyStart = probe
                let stops: Set<Character> = [";", "&", "%"]
                while probe < characters.count, !stops.contains(characters[probe]), !characters[probe].isWhitespace {
                    probe += 1
                }
                guard probe > bodyStart, probe < characters.count, characters[probe] == ";" else {
                    throw ParseError.invalidReference(String(character), mark)
                }
                index = probe
            }
            index += 1
        }
    }

    /// Scans a Name strictly: the first character must satisfy NameStartChar
    /// and the rest NameChar, so `-ge` or `.pe` is rejected where the lenient
    /// continuation-character scan would accept it.
    mutating func scanStrictName(_ reader: inout Reader, at mark: Mark) throws -> String {
        guard let first = reader.peek(), first.unicodeScalars.allSatisfy(PureXML.Parsing.XMLCharacter.isNameStart) else {
            throw ParseError.expectedName(mark)
        }
        return scanName(&reader)
    }

    /// Removes a leading text declaration from an external entity's resolved
    /// text (4.3.1): the declaration is not part of the replacement text. Text
    /// without one passes through unchanged, including text whose `<?xml` is
    /// not actually a text declaration.
    func strippingTextDeclaration(_ text: String) -> String {
        guard text.hasPrefix("<?xml") else { return text }
        // Foundation-free search for the closing '?>'.
        var close = text.index(text.startIndex, offsetBy: 5)
        while close < text.endIndex {
            if text[close] == "?", text.index(after: close) < text.endIndex, text[text.index(after: close)] == ">" {
                break
            }
            close = text.index(after: close)
        }
        guard close < text.endIndex else { return text }
        let declaration = String(text[text.index(text.startIndex, offsetBy: 5) ..< close])
        guard declaration.first?.isWhitespace == true,
              PureXML.Parsing.XMLDeclaration.parseTextDeclaration(declaration) != nil
        else { return text }
        return String(text[text.index(close, offsetBy: 2)...])
    }

    /// Consumes the external subset's optional text declaration
    /// `<?xml VersionInfo? EncodingDecl S? ?>` (production 77): unlike the
    /// document's XML declaration, the version is optional, the encoding is
    /// required, and `standalone` is not allowed.
    mutating func scanTextDeclaration(_ reader: inout Reader, at mark: Mark) throws {
        // Reader copies share their pull source, so look ahead in place: only
        // '<?xml' followed by whitespace opens a text declaration ('<?xml-…'
        // is an ordinary PI target and '<?xml?>' falls through to the
        // reserved-target check).
        guard reader.matches("<?xml"), reader.peek(5)?.isWhitespace == true else {
            return
        }
        reader.consume("<?xml")
        var text = ""
        while !reader.matches("?>") {
            guard let character = reader.advance() else {
                throw ParseError.malformedDeclaration(mark)
            }
            text.append(character)
        }
        reader.consume("?>")
        guard PureXML.Parsing.XMLDeclaration.parseTextDeclaration(text) != nil else {
            throw ParseError.malformedDeclaration(mark)
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

    /// A default attribute value may reference only general entities that are
    /// already declared and internal: an undeclared, forward-declared, external,
    /// or unparsed entity in a default is not well-formed, and the referenced
    /// chain must not recurse.
    func validateDefaultValueReferences(_ value: String, at mark: Mark) throws {
        try walkDefaultReferences(value, visiting: [], at: mark)
    }

    func walkDefaultReferences(_ value: String, visiting: Set<String>, at mark: Mark) throws {
        let predefined: Set = ["amp", "lt", "gt", "quot", "apos"]
        let characters = Array(value)
        var index = 0
        while index < characters.count {
            guard characters[index] == "&" else {
                index += 1
                continue
            }
            var probe = index + 1
            if probe < characters.count, characters[probe] == "#" {
                while probe < characters.count, characters[probe] != ";" {
                    probe += 1
                }
                index = probe + 1
                continue
            }
            var name = ""
            while probe < characters.count, characters[probe] != ";" {
                name.append(characters[probe])
                probe += 1
            }
            index = probe + 1
            guard !predefined.contains(name) else { continue }
            guard !visiting.contains(name) else {
                throw ParseError.recursiveEntity(name: name, mark)
            }
            guard doctype.unparsedEntities[name] == nil, doctype.externalEntities[name] == nil else {
                throw ParseError.invalidAttributeListDeclaration(mark)
            }
            guard let replacement = doctype.entities[name] else {
                throw ParseError.undefinedEntity(name: name, mark)
            }
            try walkDefaultReferences(replacement, visiting: visiting.union([name]), at: mark)
        }
    }
}
