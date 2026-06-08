extension PureXML.Regex {
    /// A `\p{...}` / `\P{...}` Unicode category or block test. A category maps to
    /// the scalar's Unicode general category through Swift's own `generalCategory`,
    /// so no character tables are vendored; an `Is<Block>` name tests a contiguous
    /// Unicode block. An unknown name is rejected at compile time.
    struct CategoryPredicate: Equatable, Sendable {
        let name: String
        let negated: Bool

        init?(name: String, negated: Bool) {
            guard CategoryMatcher.isKnown(name) else { return nil }
            self.name = name
            self.negated = negated
        }

        func contains(_ scalar: Unicode.Scalar) -> Bool {
            let hit = CategoryMatcher.matches(name, scalar)
            return negated ? !hit : hit
        }
    }

    /// Resolves `\p{...}` names: a one-letter general-category group (`L`, `N`, ...),
    /// a two-letter category (`Lu`, `Nd`, ...), or an `Is<Block>` block name.
    enum CategoryMatcher {
        static func isKnown(_ name: String) -> Bool {
            if name.hasPrefix("Is") { return blocks[String(name.dropFirst(2))] != nil }
            return groups.contains(name) || codeValues.contains(name)
        }

        static func matches(_ name: String, _ scalar: Unicode.Scalar) -> Bool {
            if name.hasPrefix("Is") {
                guard let range = blocks[String(name.dropFirst(2))] else { return false }
                return range.contains(scalar.value)
            }
            let code = codes[scalar.properties.generalCategory] ?? "Cn"
            return name.count == 1 ? code.hasPrefix(name) : code == name
        }

        private static let groups: Set<String> = ["L", "M", "N", "P", "S", "Z", "C"]
        private static let codeValues = Set(codes.values)

        private static let codes: [Unicode.GeneralCategory: String] = [
            .uppercaseLetter: "Lu", .lowercaseLetter: "Ll", .titlecaseLetter: "Lt",
            .modifierLetter: "Lm", .otherLetter: "Lo",
            .nonspacingMark: "Mn", .spacingMark: "Mc", .enclosingMark: "Me",
            .decimalNumber: "Nd", .letterNumber: "Nl", .otherNumber: "No",
            .connectorPunctuation: "Pc", .dashPunctuation: "Pd", .openPunctuation: "Ps",
            .closePunctuation: "Pe", .initialPunctuation: "Pi", .finalPunctuation: "Pf",
            .otherPunctuation: "Po",
            .mathSymbol: "Sm", .currencySymbol: "Sc", .modifierSymbol: "Sk", .otherSymbol: "So",
            .spaceSeparator: "Zs", .lineSeparator: "Zl", .paragraphSeparator: "Zp",
            .control: "Cc", .format: "Cf", .surrogate: "Cs", .privateUse: "Co", .unassigned: "Cn",
        ]

        /// A curated set of well-known Unicode blocks. An `Is<Block>` name outside
        /// this set is rejected rather than guessed, so a pattern never matches
        /// against a fabricated range.
        private static let blocks: [String: ClosedRange<UInt32>] = [
            "BasicLatin": 0x0000 ... 0x007F,
            "Latin-1Supplement": 0x0080 ... 0x00FF,
            "LatinExtended-A": 0x0100 ... 0x017F,
            "LatinExtended-B": 0x0180 ... 0x024F,
            "IPAExtensions": 0x0250 ... 0x02AF,
            "Greek": 0x0370 ... 0x03FF,
            "GreekandCoptic": 0x0370 ... 0x03FF,
            "Cyrillic": 0x0400 ... 0x04FF,
            "Hebrew": 0x0590 ... 0x05FF,
            "Arabic": 0x0600 ... 0x06FF,
            "GeneralPunctuation": 0x2000 ... 0x206F,
            "CurrencySymbols": 0x20A0 ... 0x20CF,
            "Hiragana": 0x3040 ... 0x309F,
            "Katakana": 0x30A0 ... 0x30FF,
            "CJKUnifiedIdeographs": 0x4E00 ... 0x9FFF,
        ]
    }
}
