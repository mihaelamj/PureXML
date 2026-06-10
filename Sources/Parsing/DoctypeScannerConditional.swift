/// Conditional sections of a DTD subset (`<![INCLUDE[ ... ]]>` /
/// `<![IGNORE[ ... ]]>`, productions 61-65), split from the scanner body to
/// keep it under the length caps.
extension DTDScanner {
    /// Processes a conditional section `<![INCLUDE[ … ]]>` or `<![IGNORE[ … ]]>`.
    /// The keyword may be a parameter-entity reference, so it is parameter-expanded
    /// first; after expansion it must be exactly `INCLUDE` or `IGNORE` (case-
    /// sensitive, production 61). An INCLUDE section's declarations are scanned;
    /// an IGNORE section's body is discarded. Nested sections are handled by
    /// re-scanning the body, and an unterminated section is not well-formed.
    mutating func scanConditionalSection(_ reader: inout Reader, depth: Int, at mark: Mark) throws {
        reader.consume("<![")
        var keywordRaw = ""
        while let character = reader.peek(), character != "[" {
            keywordRaw.append(character)
            reader.advance()
        }
        guard reader.consume("[") else {
            throw ParseError.malformedDeclaration(mark)
        }
        let keyword = expandParameterReferences(keywordRaw).trimmingXMLWhitespace()
        guard keyword == "INCLUDE" || keyword == "IGNORE" else {
            throw ParseError.malformedDeclaration(mark)
        }
        guard let body = readConditionalBody(&reader) else {
            throw ParseError.malformedDeclaration(mark)
        }
        if keyword == "INCLUDE", depth < maxDepth {
            var sub = Reader(body)
            try scanDeclarations(&sub, depth: depth + 1, terminatedByBracket: false, at: mark)
        }
    }

    /// Reads the body of a conditional section up to its matching `]]>`, keeping
    /// any nested `<![ … ]]>` sections intact so an INCLUDE can re-scan them.
    /// Returns nil when the input ends before the section is balanced.
    mutating func readConditionalBody(_ reader: inout Reader) -> String? {
        var body = ""
        var nesting = 1
        while reader.peek() != nil {
            if reader.matches("<![") {
                nesting += 1
                reader.consume("<![")
                body += "<!["
            } else if reader.matches("]]>") {
                reader.consume("]]>")
                nesting -= 1
                if nesting == 0 { return body }
                body += "]]>"
            } else if let character = reader.peek() {
                body.append(character)
                reader.advance()
            }
        }
        return nil
    }
}
