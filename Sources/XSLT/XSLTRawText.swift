extension PureXML.XSLT {
    /// `disable-output-escaping`: raw text travels through the result tree
    /// bracketed by private-use sentinels, and after serialization the
    /// escaping applied inside the brackets is undone (XSLT 1.0 section 16.4,
    /// the serializer-flag technique).
    enum RawText {
        static let begin: Character = "\u{E000}"
        static let end: Character = "\u{E001}"

        static func marked(_ text: String) -> String {
            String(begin) + text + String(end)
        }

        /// The text with any raw markers removed (escaping re-enabled).
        static func stripped(_ text: String) -> String {
            guard text.contains(begin) || text.contains(end) else { return text }
            return String(text.filter { $0 != begin && $0 != end })
        }

        /// Removes the sentinels, undoing the serializer's escaping between
        /// them. Text outside sentinel pairs passes through untouched.
        static func resolve(_ serialized: String) -> String {
            guard serialized.contains(begin) else { return serialized }
            var result = ""
            var rawRegion = ""
            var inRaw = false
            for character in serialized {
                switch character {
                case begin:
                    inRaw = true
                case end:
                    result += unescaped(rawRegion)
                    rawRegion = ""
                    inRaw = false
                default:
                    if inRaw {
                        rawRegion.append(character)
                    } else {
                        result.append(character)
                    }
                }
            }
            return result + unescaped(rawRegion)
        }

        /// The serializer's own escape forms, decoded back.
        private static let escapes: [String: Character] = [
            "quot": "\"", "lt": "<", "gt": ">", "amp": "&",
            "#xD": "\r", "#x9": "\t", "#xA": "\n", "#13": "\r", "#9": "\t", "#10": "\n",
        ]

        /// Undoes the XML/HTML serializer escapes.
        private static func unescaped(_ text: String) -> String {
            guard text.contains("&") else { return text }
            var result = ""
            var index = text.startIndex
            while index < text.endIndex {
                guard text[index] == "&",
                      let semicolon = text[index...].firstIndex(of: ";"),
                      let decoded = escapes[String(text[text.index(after: index) ..< semicolon])]
                else {
                    result.append(text[index])
                    index = text.index(after: index)
                    continue
                }
                result.append(decoded)
                index = text.index(after: semicolon)
            }
            return result
        }
    }
}
