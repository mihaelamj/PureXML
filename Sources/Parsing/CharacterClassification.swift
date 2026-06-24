extension StringProtocol {
    /// Trims leading and trailing XML whitespace without Foundation.
    func trimmingXMLWhitespace() -> String {
        var slice = self[...]
        while let first = slice.first, first.isXMLWhitespace {
            slice = slice.dropFirst()
        }
        while let last = slice.last, last.isXMLWhitespace {
            slice = slice.dropLast()
        }
        return String(slice)
    }
}

extension Character {
    private typealias XML = PureXML.Parsing.XMLCharacter

    /// XML S production: space, tab, carriage return, line feed.
    var isXMLWhitespace: Bool {
        unicodeScalars.count == 1 && unicodeScalars.first.map(XML.isWhitespace) == true
    }

    /// Whether this character may start an XML name. A grapheme qualifies when its
    /// first scalar is a NameStartChar and any trailing scalars (combining marks)
    /// are NameChar.
    var isXMLNameStart: Bool {
        guard let first = unicodeScalars.first, XML.isNameStart(first) else { return false }
        return unicodeScalars.dropFirst().allSatisfy(XML.isNameChar)
    }

    /// Whether this character may continue an XML name (every scalar a NameChar).
    var isXMLNameContinuation: Bool {
        !unicodeScalars.isEmpty && unicodeScalars.allSatisfy(XML.isNameChar)
    }
}
