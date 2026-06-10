/// The C14N escaping rules, split from the canonicalizer body to keep it
/// under the length caps: text escapes & < > and CR; attribute values escape
/// & < " TAB LF CR. Both iterate Unicode scalars so a CR that clustered with
/// a following LF is still escaped.
extension PureXML.Canonical.Canonicalizer {
    // MARK: Escaping

    static func escapeText(_ value: String) -> String {
        // Scalar-level: a CR that clustered with a following LF must still
        // be escaped, so the loop cannot compare grapheme Characters.
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\r": result += "&#xD;"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func escapeAttribute(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case "\"": result += "&quot;"
            case "\t": result += "&#x9;"
            case "\n": result += "&#xA;"
            case "\r": result += "&#xD;"
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}
