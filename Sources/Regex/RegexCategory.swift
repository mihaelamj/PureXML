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
            let code = XSDCategory.generalCategoryCode(scalar)
            if name.hasPrefix("Is") {
                guard let range = blocks[String(name.dropFirst(2))] else { return false }
                return range.contains(scalar.value)
            }
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

        /// The complete set of Unicode block names XSD 1.0 admits in
        /// `\p{Is<Block>}` (the Unicode 3.1 blocks the regular-expression appendix
        /// fixes), each mapped to its code-point range. The set is exhaustive: an
        /// `Is<Block>` name outside it is no XSD block and is rejected at compile
        /// time (`isMalformedProperty` is gone; the predicate's presence here is the
        /// sole authority), so a pattern never matches against a fabricated range.
        /// XSD 1.0 freezes this list at Unicode 3.1, so a block introduced later
        /// (e.g. `CyrillicSupplement`) is by design not an XSD 1.0 block and is
        /// rejected, even though some processors accept any `Is[A-Za-z0-9-]+`
        /// leniently. This is a deliberate spec-strict choice, not an oversight.
        /// The three surrogate blocks are listed so a pattern naming them still
        /// compiles, but their ranges hold no scalar value, so they match nothing.
        /// `Specials` uses the main `FFF0..FFFD` range (the spec's separate `FEFF`
        /// half is the byte-order mark, not matched here). `GreekandCoptic` is the
        /// later Unicode rename of `Greek`, kept as a lenient alias.
        private static let blocks: [String: ClosedRange<UInt32>] = [
            "BasicLatin": 0x0000 ... 0x007F,
            "Latin-1Supplement": 0x0080 ... 0x00FF,
            "LatinExtended-A": 0x0100 ... 0x017F,
            "LatinExtended-B": 0x0180 ... 0x024F,
            "IPAExtensions": 0x0250 ... 0x02AF,
            "SpacingModifierLetters": 0x02B0 ... 0x02FF,
            "CombiningDiacriticalMarks": 0x0300 ... 0x036F,
            "Greek": 0x0370 ... 0x03FF,
            "GreekandCoptic": 0x0370 ... 0x03FF,
            "Cyrillic": 0x0400 ... 0x04FF,
            "Armenian": 0x0530 ... 0x058F,
            "Hebrew": 0x0590 ... 0x05FF,
            "Arabic": 0x0600 ... 0x06FF,
            "Syriac": 0x0700 ... 0x074F,
            "Thaana": 0x0780 ... 0x07BF,
            "Devanagari": 0x0900 ... 0x097F,
            "Bengali": 0x0980 ... 0x09FF,
            "Gurmukhi": 0x0A00 ... 0x0A7F,
            "Gujarati": 0x0A80 ... 0x0AFF,
            "Oriya": 0x0B00 ... 0x0B7F,
            "Tamil": 0x0B80 ... 0x0BFF,
            "Telugu": 0x0C00 ... 0x0C7F,
            "Kannada": 0x0C80 ... 0x0CFF,
            "Malayalam": 0x0D00 ... 0x0D7F,
            "Sinhala": 0x0D80 ... 0x0DFF,
            "Thai": 0x0E00 ... 0x0E7F,
            "Lao": 0x0E80 ... 0x0EFF,
            "Tibetan": 0x0F00 ... 0x0FFF,
            "Myanmar": 0x1000 ... 0x109F,
            "Georgian": 0x10A0 ... 0x10FF,
            "HangulJamo": 0x1100 ... 0x11FF,
            "Ethiopic": 0x1200 ... 0x137F,
            "Cherokee": 0x13A0 ... 0x13FF,
            "UnifiedCanadianAboriginalSyllabics": 0x1400 ... 0x167F,
            "Ogham": 0x1680 ... 0x169F,
            "Runic": 0x16A0 ... 0x16FF,
            "Khmer": 0x1780 ... 0x17FF,
            "Mongolian": 0x1800 ... 0x18AF,
            "LatinExtendedAdditional": 0x1E00 ... 0x1EFF,
            "GreekExtended": 0x1F00 ... 0x1FFF,
            "GeneralPunctuation": 0x2000 ... 0x206F,
            "SuperscriptsandSubscripts": 0x2070 ... 0x209F,
            "CurrencySymbols": 0x20A0 ... 0x20CF,
            "CombiningMarksforSymbols": 0x20D0 ... 0x20FF,
            "LetterlikeSymbols": 0x2100 ... 0x214F,
            "NumberForms": 0x2150 ... 0x218F,
            "Arrows": 0x2190 ... 0x21FF,
            "MathematicalOperators": 0x2200 ... 0x22FF,
            "MiscellaneousTechnical": 0x2300 ... 0x23FF,
            "ControlPictures": 0x2400 ... 0x243F,
            "OpticalCharacterRecognition": 0x2440 ... 0x245F,
            "EnclosedAlphanumerics": 0x2460 ... 0x24FF,
            "BoxDrawing": 0x2500 ... 0x257F,
            "BlockElements": 0x2580 ... 0x259F,
            "GeometricShapes": 0x25A0 ... 0x25FF,
            "MiscellaneousSymbols": 0x2600 ... 0x26FF,
            "Dingbats": 0x2700 ... 0x27BF,
            "BraillePatterns": 0x2800 ... 0x28FF,
            "CJKRadicalsSupplement": 0x2E80 ... 0x2EFF,
            "KangxiRadicals": 0x2F00 ... 0x2FDF,
            "IdeographicDescriptionCharacters": 0x2FF0 ... 0x2FFF,
            "CJKSymbolsandPunctuation": 0x3000 ... 0x303F,
            "Hiragana": 0x3040 ... 0x309F,
            "Katakana": 0x30A0 ... 0x30FF,
            "Bopomofo": 0x3100 ... 0x312F,
            "HangulCompatibilityJamo": 0x3130 ... 0x318F,
            "Kanbun": 0x3190 ... 0x319F,
            "BopomofoExtended": 0x31A0 ... 0x31BF,
            "EnclosedCJKLettersandMonths": 0x3200 ... 0x32FF,
            "CJKCompatibility": 0x3300 ... 0x33FF,
            "CJKUnifiedIdeographsExtensionA": 0x3400 ... 0x4DB5,
            "CJKUnifiedIdeographs": 0x4E00 ... 0x9FFF,
            "YiSyllables": 0xA000 ... 0xA48F,
            "YiRadicals": 0xA490 ... 0xA4CF,
            "HangulSyllables": 0xAC00 ... 0xD7A3,
            "PrivateUse": 0xE000 ... 0xF8FF,
            "CJKCompatibilityIdeographs": 0xF900 ... 0xFAFF,
            "AlphabeticPresentationForms": 0xFB00 ... 0xFB4F,
            "ArabicPresentationForms-A": 0xFB50 ... 0xFDFF,
            "CombiningHalfMarks": 0xFE20 ... 0xFE2F,
            "CJKCompatibilityForms": 0xFE30 ... 0xFE4F,
            "SmallFormVariants": 0xFE50 ... 0xFE6F,
            "ArabicPresentationForms-B": 0xFE70 ... 0xFEFF,
            "HalfwidthandFullwidthForms": 0xFF00 ... 0xFFEF,
            "Specials": 0xFFF0 ... 0xFFFD,
            // Surrogate blocks: valid XSD block names whose ranges hold no scalar
            // value (lone surrogates are not Unicode scalars), so they match nothing.
            "HighSurrogates": 0xD800 ... 0xDB7F,
            "HighPrivateUseSurrogates": 0xDB80 ... 0xDBFF,
            "LowSurrogates": 0xDC00 ... 0xDFFF,
            // Supplementary-plane blocks (Unicode 3.1, beyond the BMP).
            "OldItalic": 0x10300 ... 0x1032F,
            "Gothic": 0x10330 ... 0x1034F,
            "Deseret": 0x10400 ... 0x1044F,
            "ByzantineMusicalSymbols": 0x1D000 ... 0x1D0FF,
            "MusicalSymbols": 0x1D100 ... 0x1D1FF,
            "MathematicalAlphanumericSymbols": 0x1D400 ... 0x1D7FF,
            "CJKUnifiedIdeographsExtensionB": 0x20000 ... 0x2A6D6,
            "CJKCompatibilityIdeographsSupplement": 0x2F800 ... 0x2FA1F,
            "Tags": 0xE0000 ... 0xE007F,
        ]
    }
}
