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
        // The spec reserves conditional sections for the external subset;
        // accepting them internally is a feature the strict profile disables.
        if limits.strictInternalSubset, !inExternalContext {
            throw ParseError.malformedDeclaration(reader.mark)
        }
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

    /// VC: Proper Group/PE Nesting. A parameter entity used in a content model
    /// must contain balanced parentheses, so a group cannot open in one
    /// replacement text and close in another. Recorded as a validity finding.
    mutating func checkGroupNesting(_ rawModel: String, element: String) {
        guard rawModel.contains("%") else { return }
        var index = rawModel.startIndex
        while index < rawModel.endIndex, let percent = rawModel[index...].firstIndex(of: "%") {
            guard let semicolon = rawModel[percent...].firstIndex(of: ";") else { return }
            let name = String(rawModel[rawModel.index(after: percent) ..< semicolon])
            if let replacement = doctype.parameterEntities[name] {
                let opens = replacement.count(where: { $0 == "(" })
                let closes = replacement.count(where: { $0 == ")" })
                if opens != closes {
                    doctype.validityFindings.append(PureXML.Parsing.ValidityFinding(
                        "the content model of '\(element)' uses parameter entity '%\(name);' with improper group/PE nesting",
                        subject: element,
                    ))
                }
            }
            index = rawModel.index(after: semicolon)
        }
    }

    /// WFC: No Recursion, checked at declaration: no parsed entity (general or
    /// parameter) may reference itself directly or indirectly through the
    /// stored replacement texts.
    func checkEntityRecursion(at mark: Mark) throws {
        var visiting: Set<String> = []
        var cleared: Set<String> = []
        for key in doctype.entities.keys.sorted() {
            try walkEntityGraph("ge:" + key, visiting: &visiting, cleared: &cleared, at: mark)
        }
        for key in doctype.parameterEntities.keys.sorted() {
            try walkEntityGraph("pe:" + key, visiting: &visiting, cleared: &cleared, at: mark)
        }
    }

    private func walkEntityGraph(_ node: String, visiting: inout Set<String>, cleared: inout Set<String>, at mark: Mark) throws {
        guard !cleared.contains(node) else { return }
        guard visiting.insert(node).inserted else {
            throw ParseError.recursiveEntity(name: String(node.dropFirst(3)), mark)
        }
        defer {
            visiting.remove(node)
            cleared.insert(node)
        }
        let name = String(node.dropFirst(3))
        let value = node.hasPrefix("ge:") ? doctype.entities[name] : doctype.parameterEntities[name]
        guard let value else { return }
        for reference in entityReferences(in: value) {
            try walkEntityGraph(reference, visiting: &visiting, cleared: &cleared, at: mark)
        }
    }

    /// The `ge:`/`pe:`-tagged references in a replacement text, with CDATA
    /// sections shielded and predefined entities skipped.
    private func entityReferences(in text: String) -> [String] {
        let predefined: Set = ["amp", "lt", "gt", "quot", "apos"]
        var references: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index...].hasPrefix("<![CDATA[") {
                var cursor = text.index(index, offsetBy: 9)
                while cursor < text.endIndex, !text[cursor...].hasPrefix("]]>") {
                    cursor = text.index(after: cursor)
                }
                index = cursor < text.endIndex ? text.index(cursor, offsetBy: 3) : text.endIndex
                continue
            }
            let character = text[index]
            guard character == "&" || character == "%" else {
                index = text.index(after: index)
                continue
            }
            guard let semicolon = text[index...].firstIndex(of: ";") else { return references }
            let body = String(text[text.index(after: index) ..< semicolon])
            if character == "&", !body.hasPrefix("#"), !predefined.contains(body) {
                references.append("ge:" + body)
            } else if character == "%", !body.isEmpty {
                references.append("pe:" + body)
            }
            index = text.index(after: semicolon)
        }
        return references
    }

    /// Whether the text after a percent sign opens a parameter-entity
    /// reference: a name-start character with a semicolon somewhere ahead.
    private func isReferenceStart(_ text: String, after index: String.Index) -> Bool {
        let nameStart = text.index(after: index)
        guard nameStart < text.endIndex,
              text[nameStart].unicodeScalars.allSatisfy(PureXML.Parsing.XMLCharacter.isNameStart)
        else { return false }
        return text[nameStart...].firstIndex(of: ";") != nil
    }

    /// Under the strict profile, a parameter-entity reference inside a markup
    /// declaration in the internal subset is rejected (WFC: PEs in Internal
    /// Subset); between declarations it stays legal (production 28a DeclSep).
    /// `skippingQuoted` is set for `<!ATTLIST>` bodies, where a quoted default
    /// value is an AttValue in which `%` is literal text, not a reference.
    func checkStrictSubsetReferences(_ text: String, skippingQuoted: Bool = false, at mark: Mark) throws {
        guard limits.strictInternalSubset, !inExternalContext else { return }
        var quote: Character?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if let open = quote {
                if character == open { quote = nil }
                index = text.index(after: index)
                continue
            }
            if skippingQuoted, character == "\"" || character == "'" {
                quote = character
                index = text.index(after: index)
                continue
            }
            if character == "%", isReferenceStart(text, after: index) {
                throw ParseError.malformedDeclaration(mark)
            }
            index = text.index(after: index)
        }
    }
}
