/// The start-tag attribute scanners, in their own file to keep the reader's
/// type body under the length cap. Behavior is part of EventReader proper.
extension PureXML.Parsing.EventReader {
    mutating func scanAttributes() throws -> [PureXML.Model.Attribute] {
        var attributes: [PureXML.Model.Attribute] = []
        var seen: Set<String> = []
        while true {
            reader.skipSpace()
            guard let next = reader.peek(), next != ">", next != "/" else {
                return attributes
            }
            let mark = reader.mark
            let name = try scanName()
            reader.skipSpace()
            guard reader.consume("=") else {
                throw PureXML.Parsing.ParseError.expectedEquals(reader.mark)
            }
            reader.skipSpace()
            let value = try scanAttributeValue()
            guard seen.insert(name.description).inserted else {
                if recovering {
                    // Keep the element: record the duplicate and drop the later
                    // occurrence rather than failing the whole start tag.
                    diagnostics.append(PureXML.Parsing.Diagnostic(PureXML.Parsing.ParseError.duplicateAttribute(name: name.description, mark)))
                    continue
                }
                throw PureXML.Parsing.ParseError.duplicateAttribute(name: name.description, mark)
            }
            attributes.append(PureXML.Model.Attribute(name: name, value: value))
            // A following attribute needs whitespace before it.
            if let next = reader.peek(), next != ">", next != "/", next != "?", !next.isWhitespace {
                throw PureXML.Parsing.ParseError.missingSpaceBeforeAttribute(reader.mark)
            }
        }
    }

    mutating func scanAttributeValue() throws -> String {
        let mark = reader.mark
        guard let quote = reader.peek(), quote == "\"" || quote == "'" else {
            throw PureXML.Parsing.ParseError.unquotedAttributeValue(reader.mark)
        }
        reader.advance()
        var raw = ""
        var length = 0
        while let character = reader.peek(), character != quote {
            length += 1
            try checkContent(length, mark)
            if character == "<" {
                throw PureXML.Parsing.ParseError.rawLessThanInAttribute(reader.mark)
            }
            guard character.unicodeScalars.allSatisfy(PureXML.Parsing.XMLCharacter.isChar) else {
                throw PureXML.Parsing.ParseError.invalidCharacter(reader.mark)
            }
            raw.append(character)
            reader.advance()
        }
        guard reader.consume(String(quote)) else {
            throw PureXML.Parsing.ParseError.unexpectedEndOfInput(reader.mark)
        }
        return try PureXML.Parsing.EntityDecoder.decode(raw, entities: referencableEntities, budget: &entityBudget, at: mark)
    }
}
