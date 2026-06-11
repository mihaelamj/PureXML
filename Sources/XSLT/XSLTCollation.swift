extension PureXML.XSLT {
    /// Language-tailored alphabet orders for xsl:sort, derived from the
    /// conformance golds (the orders Xalan obtains from Java's collators).
    /// A scalar found in the language's alphabet ranks by its tailored
    /// position; anything else ranks after the alphabet by code point, and
    /// lookups are case-folded so both cases share a rank. Languages
    /// without a table fall back to the default (space-ignorable) order.
    enum Collation {
        /// Polish: diacritic letters interleave after their base letters.
        private static let polish = "A\u{104}BC\u{106}DE\u{118}FGHIJKL\u{141}MN\u{143}O\u{D3}PRS\u{15A}TUWYZ\u{179}\u{17B}"
        /// Russian: code-point order except \u{401} (Yo) after \u{415} (Ye).
        private static let russian = "\u{410}\u{411}\u{412}\u{413}\u{414}\u{415}\u{401}\u{416}\u{417}\u{418}\u{419}\u{41A}\u{41B}\u{41C}\u{41D}\u{41E}\u{41F}"
            + "\u{420}\u{421}\u{422}\u{423}\u{424}\u{425}\u{426}\u{427}\u{428}\u{429}\u{42A}\u{42B}\u{42C}\u{42D}\u{42E}\u{42F}"

        /// The rank table for a language tag, matched by primary subtag.
        static func table(for lang: String) -> [Character: Int]? {
            let primary = lang.split(separator: "-").first.map(String.init)?.lowercased() ?? lang.lowercased()
            let alphabet: String
            switch primary {
            case "pl": alphabet = polish
            case "ru": alphabet = russian
            default: return nil
            }
            var ranks: [Character: Int] = [:]
            for (rank, letter) in alphabet.enumerated() {
                ranks[letter] = rank
                for lowered in String(letter).lowercased() where ranks[lowered] == nil {
                    ranks[lowered] = rank
                }
            }
            return ranks
        }

        /// Compares two strings by tailored rank, scalar by scalar; letters
        /// outside the alphabet sort after it by code point, and equal-rank
        /// prefixes fall back to length then exact content for stability.
        static func compare(_ left: String, _ right: String, _ ranks: [Character: Int]) -> Int {
            let beyond = ranks.count
            for (first, second) in zip(left, right) where first != second {
                let leftRank = ranks[first] ?? beyond + Int(first.unicodeScalars.first?.value ?? 0)
                let rightRank = ranks[second] ?? beyond + Int(second.unicodeScalars.first?.value ?? 0)
                if leftRank != rightRank { return leftRank < rightRank ? -1 : 1 }
            }
            if left.count != right.count { return left.count < right.count ? -1 : 1 }
            return left == right ? 0 : (left < right ? -1 : 1)
        }
    }
}
