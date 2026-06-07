extension PureXML.Parsing {
    /// Decodes XML references inside text and attribute values: the five
    /// predefined entities and decimal/hex character references. General entity
    /// declarations from a DTD are deliberately not supported (DTD processing is
    /// off by default), so any other `&name;` is rejected rather than expanded.
    enum EntityDecoder {
        static func decode(_ raw: String, at mark: Mark) throws -> String {
            guard raw.contains("&") else { return raw }
            var result = ""
            var iterator = raw.startIndex
            while iterator < raw.endIndex {
                let character = raw[iterator]
                guard character == "&" else {
                    result.append(character)
                    iterator = raw.index(after: iterator)
                    continue
                }
                guard let semicolon = raw[iterator...].firstIndex(of: ";") else {
                    throw PureXML.Parsing.ParseError.invalidReference(String(raw[iterator...]), mark)
                }
                let body = String(raw[raw.index(after: iterator) ..< semicolon])
                try result.append(resolve(body, at: mark))
                iterator = raw.index(after: semicolon)
            }
            return result
        }

        private static func resolve(_ body: String, at mark: Mark) throws -> Character {
            switch body {
            case "amp": return "&"
            case "lt": return "<"
            case "gt": return ">"
            case "quot": return "\""
            case "apos": return "'"
            default:
                break
            }

            guard body.hasPrefix("#") else {
                throw PureXML.Parsing.ParseError.invalidReference("&\(body);", mark)
            }
            let digits = String(body.dropFirst())
            let scalarValue: UInt32? = if digits.hasPrefix("x") || digits.hasPrefix("X") {
                UInt32(digits.dropFirst(), radix: 16)
            } else {
                UInt32(digits, radix: 10)
            }
            guard let value = scalarValue, let scalar = Unicode.Scalar(value) else {
                throw PureXML.Parsing.ParseError.invalidReference("&\(body);", mark)
            }
            return Character(scalar)
        }
    }
}
