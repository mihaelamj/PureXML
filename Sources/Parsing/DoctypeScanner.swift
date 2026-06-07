extension PureXML.Parsing {
    /// Consumes a `<!DOCTYPE ...>` declaration.
    ///
    /// When DTD processing is disabled (the default), the whole declaration is
    /// refused, which keeps the XXE and entity-expansion threat classes closed.
    /// When enabled, only internal general-entity declarations
    /// (`<!ENTITY name "value">`) are honored. External entities are skipped (not
    /// stored), so referencing one later fails as undefined; element, attribute,
    /// and notation declarations are skipped as well. Parameter entities are not
    /// supported and their declarations and references are skipped.
    enum DoctypeScanner {
        static func scan(_ reader: inout Reader, limits: Limits) throws -> DocumentType {
            let mark = reader.mark
            guard limits.allowDoctype else {
                throw ParseError.unsupportedDoctype(mark)
            }
            reader.consume("<!DOCTYPE")
            // Skip the root-element name and any external identifier up to the
            // internal subset or the closing bracket.
            while let character = reader.peek(), character != "[", character != ">" {
                reader.advance()
            }
            var doctype = DocumentType()
            if reader.consume("[") {
                try scanInternalSubset(&reader, into: &doctype, at: mark)
            }
            reader.skipSpace()
            guard reader.consume(">") else {
                throw ParseError.unterminatedTag(mark)
            }
            return doctype
        }

        private static func scanInternalSubset(
            _ reader: inout Reader,
            into doctype: inout DocumentType,
            at mark: Mark,
        ) throws {
            while true {
                reader.skipSpace()
                guard let character = reader.peek() else {
                    throw ParseError.unsupportedDoctype(mark)
                }
                if reader.consume("]") {
                    return
                }
                if reader.matches("<!ENTITY") {
                    try scanEntityDeclaration(&reader, into: &doctype.entities)
                } else if reader.matches("<!ELEMENT") {
                    scanElementDeclaration(&reader, into: &doctype.elementModels)
                } else if reader.matches("<!--") {
                    skip(&reader, until: "-->")
                } else if reader.matches("<?") {
                    skip(&reader, until: "?>")
                } else if reader.matches("<!") {
                    skip(&reader, until: ">")
                } else if character == "%" {
                    skip(&reader, until: ";")
                } else {
                    reader.advance()
                }
            }
        }

        private static func scanElementDeclaration(
            _ reader: inout Reader,
            into elementModels: inout [String: String],
        ) {
            reader.consume("<!ELEMENT")
            reader.skipSpace()
            let name = scanName(&reader)
            reader.skipSpace()
            var model = ""
            while let character = reader.peek(), character != ">" {
                model.append(character)
                reader.advance()
            }
            reader.consume(">")
            if !name.isEmpty {
                elementModels[name] = model.trimmingXMLWhitespace()
            }
        }

        private static func scanEntityDeclaration(
            _ reader: inout Reader,
            into entities: inout [String: String],
        ) throws {
            reader.consume("<!ENTITY")
            reader.skipSpace()
            // Parameter-entity declaration (`<!ENTITY % name ...>`): not supported.
            if reader.consume("%") {
                skip(&reader, until: ">")
                return
            }
            let name = scanName(&reader)
            reader.skipSpace()
            guard let quote = reader.peek(), quote == "\"" || quote == "'" else {
                // External entity (SYSTEM/PUBLIC) or malformed: skip, do not store.
                skip(&reader, until: ">")
                return
            }
            reader.advance()
            var value = ""
            while let character = reader.peek(), character != quote {
                value.append(character)
                reader.advance()
            }
            reader.consume(String(quote))
            skip(&reader, until: ">")
            if !name.isEmpty {
                entities[name] = value
            }
        }

        private static func scanName(_ reader: inout Reader) -> String {
            var name = ""
            while let character = reader.peek(), character.isXMLNameContinuation {
                name.append(character)
                reader.advance()
            }
            return name
        }

        private static func skip(_ reader: inout Reader, until terminator: String) {
            while reader.peek() != nil, !reader.matches(terminator) {
                reader.advance()
            }
            reader.consume(terminator)
        }
    }
}
