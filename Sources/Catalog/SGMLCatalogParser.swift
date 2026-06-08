/// A cursor over the keyword/string tokens of an SGML catalog. File-scope and
/// private.
private struct SGMLScanner {
    private let tokens: [String]
    private var index = 0

    init(_ tokens: [String]) {
        self.tokens = tokens
    }

    mutating func next() -> String? {
        guard index < tokens.count else { return nil }
        defer { index += 1 }
        return tokens[index]
    }
}

/// Accumulates SGML catalog entries as the token stream is consumed. File-scope
/// and private.
private struct SGMLBuilder {
    var systemMap: [String: String] = [:]
    var publicMap: [String: String] = [:]
    var delegatePublic: [PureXML.Catalog.DelegateRule] = []
    var nextCatalogs: [String] = []
    var preferPublic = true
    var base: String

    mutating func apply(_ keyword: String, _ scanner: inout SGMLScanner) {
        let upper = keyword.uppercased()
        if applyPair(upper, &scanner) { return }
        applySingle(upper, &scanner)
    }

    private mutating func applyPair(_ keyword: String, _ scanner: inout SGMLScanner) -> Bool {
        switch keyword {
        case "PUBLIC":
            if let id = scanner.next(), let uri = scanner.next() { publicMap[id] = resolve(uri) }
        case "SYSTEM":
            if let id = scanner.next(), let uri = scanner.next() { systemMap[id] = resolve(uri) }
        case "DELEGATE":
            if let prefix = scanner.next(), let catalog = scanner.next() {
                delegatePublic.append(PureXML.Catalog.DelegateRule(startString: prefix, catalog: resolve(catalog)))
            }
        default:
            return false
        }
        return true
    }

    private mutating func applySingle(_ keyword: String, _ scanner: inout SGMLScanner) {
        switch keyword {
        case "CATALOG":
            if let catalog = scanner.next() { nextCatalogs.append(resolve(catalog)) }
        case "BASE":
            if let declared = scanner.next() { base = resolve(declared) }
        case "OVERRIDE":
            if let value = scanner.next() { preferPublic = value.uppercased() == "YES" }
        default:
            break
        }
    }

    private func resolve(_ uri: String) -> String {
        base.isEmpty ? uri : PureXML.XInclude.URIReference.resolve(uri, against: base)
    }

    func resolver() -> PureXML.Catalog.Resolver {
        PureXML.Catalog.Resolver(
            systemMap: systemMap,
            publicMap: publicMap,
            uriMap: [:],
            rewriteSystem: [],
            rewriteURI: [],
            delegatePublic: delegatePublic,
            nextCatalogs: nextCatalogs,
            preferPublic: preferPublic,
        )
    }
}

extension PureXML.Catalog {
    /// Parses a legacy SGML Open (OASIS TR 9401) catalog: keyword entries such as
    /// `PUBLIC "fpi" "uri"`, `SYSTEM "sid" "uri"`, `DELEGATE "prefix" "catalog"`,
    /// `CATALOG "catalog"`, `BASE "uri"`, and `OVERRIDE YES|NO`, with `-- comment --`
    /// delimiters. Replacement URIs are resolved against the in-scope `BASE` (and
    /// the supplied `baseURI`). Unrecognized keywords are skipped tolerantly.
    enum SGMLCatalogParser {
        static func parse(_ text: String, baseURI: String) -> Resolver {
            var scanner = SGMLScanner(tokenize(text))
            var builder = SGMLBuilder(base: baseURI)
            while let keyword = scanner.next() {
                builder.apply(keyword, &scanner)
            }
            return builder.resolver()
        }

        /// Splits SGML catalog text into keyword and string tokens, honoring quotes
        /// and `-- ... --` comments.
        private static func tokenize(_ text: String) -> [String] {
            var tokens: [String] = []
            let chars = Array(text)
            var index = 0
            while index < chars.count {
                let character = chars[index]
                if character.isWhitespace {
                    index += 1
                } else if character == "-", index + 1 < chars.count, chars[index + 1] == "-" {
                    index = skipComment(chars, from: index + 2)
                } else if character == "\"" || character == "'" {
                    let (token, next) = readQuoted(chars, from: index + 1, quote: character)
                    tokens.append(token)
                    index = next
                } else {
                    let (token, next) = readBare(chars, from: index)
                    tokens.append(token)
                    index = next
                }
            }
            return tokens
        }

        private static func skipComment(_ chars: [Character], from start: Int) -> Int {
            var index = start
            while index + 1 < chars.count, !(chars[index] == "-" && chars[index + 1] == "-") {
                index += 1
            }
            return Swift.min(index + 2, chars.count)
        }

        private static func readQuoted(_ chars: [Character], from start: Int, quote: Character) -> (String, Int) {
            var index = start
            var token = ""
            while index < chars.count, chars[index] != quote {
                token.append(chars[index])
                index += 1
            }
            return (token, Swift.min(index + 1, chars.count))
        }

        private static func readBare(_ chars: [Character], from start: Int) -> (String, Int) {
            var index = start
            var token = ""
            while index < chars.count, !chars[index].isWhitespace {
                token.append(chars[index])
                index += 1
            }
            return (token, index)
        }
    }
}
