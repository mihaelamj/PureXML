/// The start-tag attribute scanners, in their own file to keep the reader's
/// type body under the length cap. Behavior is part of EventReader proper.
extension PureXML.Parsing.EventReader {
    mutating func scanAttributes() throws -> [PureXML.Model.Attribute] {
        var attributes: [PureXML.Model.Attribute] = []
        var seen: Set<String> = []
        while true {
            reader.skipSpace()
            // Byte dispatch keeps the buffer empty so scanName() reaches its
            // byte fast path; the Character peek is the off-fast-path fallback.
            if let byte = reader.peekByte() {
                if byte == 0x3E || byte == 0x2F { return attributes } // '>' or '/'
            } else {
                guard let next = reader.peek(), next != ">", next != "/" else {
                    return attributes
                }
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
            // A following attribute needs whitespace before it. Check the raw
            // byte when on the fast path to avoid buffering the next name char.
            if let byte = reader.peekByte() {
                // '>', '/', '?', or whitespace may legally follow a value; any
                // other byte means a missing separator before the next attribute.
                let isSeparator = byte == 0x3E || byte == 0x2F || byte == 0x3F
                    || byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
                if !isSeparator {
                    throw PureXML.Parsing.ParseError.missingSpaceBeforeAttribute(reader.mark)
                }
            } else if let next = reader.peek(), next != ">", next != "/", next != "?", !next.isWhitespace {
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
        let quoteByte: UInt8 = quote == "\"" ? 0x22 : 0x27
        var raw = ""
        var length = 0
        while true {
            // Bulk byte runs first: plain ASCII value text (the common case)
            // skips the per-character machinery; the run stops before the
            // quote, '<', CR, or any byte the Character path must inspect.
            if let run = reader.attributeRunBytes(quote: quoteByte) {
                length += run.utf8.count
                try checkContent(length, mark)
                raw += run
                continue
            }
            guard let character = reader.peek(), character != quote else { break }
            length += 1
            try checkContent(length, mark)
            if character == "<" {
                throw PureXML.Parsing.ParseError.rawLessThanInAttribute(reader.mark)
            }
            guard character.unicodeScalars.allSatisfy(PureXML.Parsing.XMLCharacter.isChar) else {
                throw PureXML.Parsing.ParseError.invalidCharacter(reader.mark)
            }
            // 3.3.3: a literal whitespace character in an attribute value
            // normalizes to a space; this happens before reference decoding,
            // so whitespace that arrives via a character reference survives.
            raw.append(character.isXMLWhitespace ? " " : character)
            reader.advance()
        }
        guard reader.consume(String(quote)) else {
            throw PureXML.Parsing.ParseError.unexpectedEndOfInput(reader.mark)
        }
        return try decodeReferences(raw, at: mark)
    }
}
