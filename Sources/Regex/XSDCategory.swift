extension PureXML.Regex {
    /// Unicode general categories as XSD 1.0 regular expressions see them
    /// (Datatypes Appendix F). Category and block escapes (`\p{...}`) and the
    /// multi-character escapes `\d`, `\w`, and friends are defined over the
    /// Unicode database. The W3C conformance corpus (XSTS) is internally
    /// consistent only at Unicode 3.2, so the repertoire is pinned there (see
    /// ``assignedInUnicode32``): a code point unassigned in 3.2 reports `Cn` and
    /// so matches `\D`/`\W`, even where the running platform now assigns it.
    ///
    /// For code points whose 3.2-era category differs from the running platform's
    /// (for example the ceiling and floor brackets, `Sm` in 3.2 but `Ps`/`Pe`
    /// today), ``categoryOverrides`` pins the 3.2 classification; every other
    /// assigned code point uses the platform category.
    enum XSDCategory {
        /// Code points whose XSD-era general category differs from the running
        /// platform's. The value is the XSD-era two-letter category.
        private static let categoryOverrides: [UInt32: String] = [
            0x00A7: "So", 0x00B6: "So",
            0x06DD: "Me",
            0x0F14: "So",
            0x166D: "Po", 0x17D7: "Po", 0x17DC: "Po",
            0x180B: "Cf", 0x180C: "Cf", 0x180D: "Cf",
            0x2308: "Sm", 0x2309: "Sm", 0x230A: "Sm", 0x230B: "Sm",
        ]

        /// The two-letter XSD category abbreviation for each Unicode general
        /// category. A flat translation table, not branching logic.
        private static let categoryCodes: [Unicode.GeneralCategory: String] = [
            .uppercaseLetter: "Lu", .lowercaseLetter: "Ll", .titlecaseLetter: "Lt",
            .modifierLetter: "Lm", .otherLetter: "Lo",
            .nonspacingMark: "Mn", .spacingMark: "Mc", .enclosingMark: "Me",
            .decimalNumber: "Nd", .letterNumber: "Nl", .otherNumber: "No",
            .connectorPunctuation: "Pc", .dashPunctuation: "Pd", .openPunctuation: "Ps",
            .closePunctuation: "Pe", .initialPunctuation: "Pi", .finalPunctuation: "Pf",
            .otherPunctuation: "Po",
            .mathSymbol: "Sm", .currencySymbol: "Sc", .modifierSymbol: "Sk", .otherSymbol: "So",
            .spaceSeparator: "Zs", .lineSeparator: "Zl", .paragraphSeparator: "Zp",
            .control: "Cc", .format: "Cf", .surrogate: "Cs", .privateUse: "Co",
            .unassigned: "Cn",
        ]

        static func generalCategoryCode(_ scalar: Unicode.Scalar) -> String {
            if let override = categoryOverrides[scalar.value] { return override }
            guard assignedInUnicode32(scalar.value) else { return "Cn" }
            return categoryCodes[scalar.properties.generalCategory] ?? "Cn"
        }
    }
}
