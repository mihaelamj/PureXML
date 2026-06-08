extension PureXML.Emitting {
    /// The shared XML output escaping rules, used by both the tree serializer and
    /// the incremental writer so their output is identical. Element content
    /// escapes the markup characters; attribute values additionally escape the
    /// quote and the whitespace characters as numeric references (matching
    /// libxml2), so attributes survive attribute-value normalization.
    enum Escaping {
        static func text(_ value: String) -> String {
            var result = ""
            for character in value {
                switch character {
                case "&": result += "&amp;"
                case "<": result += "&lt;"
                case ">": result += "&gt;"
                default: result.append(character)
                }
            }
            return result
        }

        static func attribute(_ value: String) -> String {
            var result = ""
            for character in value {
                switch character {
                case "&": result += "&amp;"
                case "<": result += "&lt;"
                case ">": result += "&gt;"
                case "\"": result += "&quot;"
                case "\t": result += "&#9;"
                case "\n": result += "&#10;"
                case "\r": result += "&#13;"
                default: result.append(character)
                }
            }
            return result
        }
    }
}
