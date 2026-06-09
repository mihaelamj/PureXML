extension PureXML.XSLT.XSLTParser {
    /// Parses an attribute value template: literal text with `{expr}` embedded
    /// XPath expressions, where `{{` and `}}` are literal braces.
    static func valueTemplate(_ string: String) -> PureXML.XSLT.ValueTemplate {
        var parts: [PureXML.XSLT.ValuePart] = []
        var literal = ""
        let characters = Array(string)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "{", index + 1 < characters.count, characters[index + 1] == "{" {
                literal.append("{")
                index += 2
                continue
            }
            if character == "}", index + 1 < characters.count, characters[index + 1] == "}" {
                literal.append("}")
                index += 2
                continue
            }
            if character == "{" {
                if !literal.isEmpty { parts.append(.literal(literal))
                    literal = ""
                }
                index += 1
                var expression = ""
                while index < characters.count, characters[index] != "}" {
                    expression.append(characters[index])
                    index += 1
                }
                index += 1
                parts.append(.expression(expression))
                continue
            }
            literal.append(character)
            index += 1
        }
        if !literal.isEmpty { parts.append(.literal(literal)) }
        return parts
    }
}
