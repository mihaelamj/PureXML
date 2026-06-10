private typealias DecimalFormat = PureXML.XSLT.DecimalFormat

/// The digit-place counts and grouping derived from a format-number picture.
/// File scope and private.
private struct NumberLayout {
    let minInteger: Int
    let minFraction: Int
    let maxFraction: Int
    let grouping: Bool
}

extension PureXML.XSLT {
    /// The XSLT `format-number` function. Supports `0`/`#` digit places, the
    /// decimal point, grouping, and a percent suffix, honoring the symbols of the
    /// chosen `xsl:decimal-format`. Pure Swift, no Foundation.
    enum FormatNumber {
        static func format(_ value: Double, _ picture: String, _ symbols: DecimalFormat = DecimalFormat()) -> String {
            guard !value.isNaN else { return symbols.notANumber }
            if value.isInfinite { return (value < 0 ? String(symbols.minusSign) : "") + symbols.infinity }
            guard !picture.isEmpty else { return PureXML.XPath.Value.format(value) }
            let percent = picture.contains(symbols.percent)
            let pattern = picture.filter { $0 != symbols.percent }
            let parts = pattern.split(separator: symbols.decimalSeparator, maxSplits: 1, omittingEmptySubsequences: false)
            let integerPattern = String(parts.first ?? "")
            let fractionPattern = parts.count > 1 ? String(parts[1]) : ""

            let minInteger = integerPattern.count(where: { $0 == symbols.zeroDigit })
            let minFraction = fractionPattern.count(where: { $0 == symbols.zeroDigit })
            let maxFraction = fractionPattern.count(where: { $0 == symbols.zeroDigit || $0 == symbols.digit })
            let grouping = integerPattern.contains(symbols.groupingSeparator)

            var magnitude = Swift.abs(percent ? value * 100 : value)
            magnitude = round(magnitude, places: maxFraction)
            let layout = NumberLayout(minInteger: minInteger, minFraction: minFraction, maxFraction: maxFraction, grouping: grouping)
            let rendered = render(magnitude, layout, symbols)
            return (value < 0 ? String(symbols.minusSign) : "") + rendered + (percent ? String(symbols.percent) : "")
        }

        private static func round(_ value: Double, places: Int) -> Double {
            var scale = 1.0
            for _ in 0 ..< places {
                scale *= 10
            }
            return (value * scale).rounded() / scale
        }

        private static func render(_ value: Double, _ layout: NumberLayout, _ symbols: DecimalFormat) -> String {
            let integerValue = Int(value)
            var integerDigits = String(integerValue)
            while integerDigits.count < Swift.max(1, layout.minInteger) {
                integerDigits = "0" + integerDigits
            }
            var integerText = digitsToSymbols(integerDigits, symbols)
            if layout.grouping { integerText = group(integerText, symbols.groupingSeparator) }

            var fractionValue = value - Double(integerValue)
            var fractionDigits = ""
            for _ in 0 ..< layout.maxFraction {
                fractionValue *= 10
                let digit = Int(fractionValue)
                fractionDigits += String(digit)
                fractionValue -= Double(digit)
            }
            while fractionDigits.count > layout.minFraction, fractionDigits.hasSuffix("0") {
                fractionDigits.removeLast()
            }
            let fractionText = digitsToSymbols(fractionDigits, symbols)
            return fractionText.isEmpty ? integerText : integerText + String(symbols.decimalSeparator) + fractionText
        }

        /// Maps ASCII digits to the format's digit set, offset from its zero-digit.
        private static func digitsToSymbols(_ digits: String, _ symbols: DecimalFormat) -> String {
            guard symbols.zeroDigit != "0", let zero = symbols.zeroDigit.unicodeScalars.first else { return digits }
            return String(digits.map { character in
                guard let value = character.wholeNumberValue, let scalar = Unicode.Scalar(zero.value + UInt32(value)) else { return character }
                return Character(scalar)
            })
        }

        private static func group(_ digits: String, _ separator: Character) -> String {
            var result = ""
            for (offset, character) in digits.reversed().enumerated() {
                if offset > 0, offset.isMultiple(of: 3) { result.append(separator) }
                result.append(character)
            }
            return String(result.reversed())
        }
    }

    /// The `xsl:key` index: each key name maps a key value to the nodes indexed
    /// under it.
    typealias KeyIndex = [String: [String: [PureXML.Model.TreeNode]]]

    /// The XSLT extensions to the XPath function library: `current`, `key`,
    /// `format-number`, and `document`, plus the `xsl:key` index they read.
    enum Library {
        /// The XSLT functions for an evaluation whose current node is `current`,
        /// reading the prebuilt `keys` index and the injected `document` loader.
        static func table(
            current: PureXML.Model.TreeNode,
            keys: KeyIndex,
            loader: @escaping (String) -> String?,
            decimalFormats: [String: PureXML.XSLT.DecimalFormat] = [:],
            documents: PureXML.XSLT.DocumentCache,
        ) -> PureXML.XPath.FunctionTable {
            PureXML.XPath.FunctionTable()
                .adding("current") { _, _ in .nodeSet([.tree(current)]) }
                .adding("format-number") { arguments, _ in
                    let name = arguments.count > 2 ? arguments[2].string : ""
                    return .string(FormatNumber.format(
                        arguments.first?.number ?? .nan,
                        arguments.count > 1 ? arguments[1].string : "",
                        decimalFormats[name] ?? PureXML.XSLT.DecimalFormat(),
                    ))
                }
                .adding("key") { arguments, _ in
                    let name = arguments.first?.string ?? ""
                    guard arguments.count > 1 else { return .nodeSet([]) }
                    // A node-set second argument unions the matches for each node's
                    // string value; any other value is used directly as a string.
                    let values: [String] = if let nodes = arguments[1].nodes {
                        nodes.compactMap(\.treeNode).map(\.stringValue)
                    } else {
                        [arguments[1].string]
                    }
                    var matched: [PureXML.Model.TreeNode] = []
                    for value in values {
                        for node in keys[name]?[value] ?? [] where !matched.contains(where: { $0 === node }) {
                            matched.append(node)
                        }
                    }
                    return .nodeSet(matched.map { .tree($0) })
                }
                .adding("document") { arguments, _ in
                    // A string or a node-set of URI references, each optionally with
                    // a `#fragment` selecting a subset of the loaded document.
                    let references: [String] = if let nodes = arguments.first?.nodes {
                        nodes.compactMap(\.treeNode).map(\.stringValue)
                    } else {
                        [arguments.first?.string ?? ""]
                    }
                    return .nodeSet(references.flatMap { documentReference($0, loader, documents) })
                }
                .adding("generate-id") { arguments, context in
                    // No argument uses the context node; an explicit empty node-set
                    // is the empty string, per the XSLT definition.
                    let node = arguments.isEmpty ? context.node.treeNode : arguments.first?.nodes?.first?.treeNode
                    guard let node else { return .string("") }
                    return .string("N\(UInt(bitPattern: ObjectIdentifier(node).hashValue))")
                }
                .adding("system-property") { arguments, _ in systemProperty(arguments.first?.string ?? "") }
                .adding("element-available") { arguments, _ in .boolean(instructionNames.contains(localPart(arguments.first?.string ?? ""))) }
                .adding("function-available") { arguments, _ in .boolean(functionNames.contains(localPart(arguments.first?.string ?? ""))) }
                .adding("unparsed-entity-uri") { _, _ in .string("") }
        }

        /// Loads one `document()` reference: the whole document, or, when the
        /// reference has a `#fragment`, the nodes its XPointer selects.
        private static func documentReference(
            _ reference: String,
            _ loader: (String) -> String?,
            _ cache: PureXML.XSLT.DocumentCache,
        ) -> [PureXML.XPath.Node] {
            let path: String
            let fragment: String?
            if let hash = reference.firstIndex(of: "#") {
                path = String(reference[..<hash])
                fragment = String(reference[reference.index(after: hash)...])
            } else {
                path = reference
                fragment = nil
            }
            if cache.trees[path] == nil {
                guard let text = loader(path), let parsed = try? PureXML.parse(text) else { return [] }
                cache.sources[path] = parsed
                cache.trees[path] = PureXML.Model.TreeNode(parsed)
            }
            guard let tree = cache.trees[path], let parsed = cache.sources[path] else { return [] }
            guard let fragment, !fragment.isEmpty else { return [.tree(tree)] }
            let selections = (try? PureXML.XPointer.evaluate(fragment, over: parsed)) ?? []
            return selections.compactMap { selection in
                guard case let .node(node) = selection else { return nil }
                return .tree(PureXML.Model.TreeNode(node))
            }
        }

        private static func localPart(_ name: String) -> String {
            name.split(separator: ":").last.map(String.init) ?? name
        }

        /// The XSLT system properties: the version is the number 1.0; the vendor
        /// strings identify this processor. Any other property is the empty string.
        private static func systemProperty(_ name: String) -> PureXML.XPath.Value {
            switch localPart(name) {
            case "version": .number(1.0)
            case "vendor": .string("PureXML")
            case "vendor-url": .string("https://github.com/mihaelamj/PureXML")
            default: .string("")
            }
        }

        /// The XSLT instruction elements this processor implements, for
        /// `element-available`.
        static let instructionNames: Set<String> = [
            "value-of", "apply-templates", "apply-imports", "call-template", "for-each", "if", "choose",
            "when", "otherwise", "element", "attribute", "copy", "copy-of", "text", "number", "comment",
            "processing-instruction", "variable", "param", "with-param", "sort", "message", "fallback",
        ]

        /// The XPath and XSLT functions this processor implements, for
        /// `function-available`.
        static let functionNames: Set<String> = [
            "last", "position", "count", "id", "local-name", "namespace-uri", "name", "string", "concat",
            "starts-with", "contains", "substring-before", "substring-after", "substring", "string-length",
            "normalize-space", "translate", "boolean", "not", "true", "false", "lang", "number", "sum",
            "floor", "ceiling", "round", "current", "document", "key", "format-number", "generate-id",
            "system-property", "element-available", "function-available", "unparsed-entity-uri",
        ]

        /// Builds the `xsl:key` index: each declared key maps every node matching
        /// its pattern to its `use` value.
        static func buildKeyIndex(stylesheet: Stylesheet, root: PureXML.Model.TreeNode) -> KeyIndex {
            var index: KeyIndex = [:]
            for key in stylesheet.keys {
                let path = key.match.hasPrefix("/") ? key.match : "//" + key.match
                guard let matchQuery = try? PureXML.XPath.Query(path),
                      let useQuery = try? PureXML.XPath.Query(key.use) else { continue }
                for node in matchQuery.nodes(over: root) {
                    let value = (try? useQuery.value(at: node).string) ?? ""
                    index[key.name, default: [:]][value, default: []].append(node)
                }
            }
            return index
        }
    }
}

extension PureXML.Emitting.Options {
    /// These options with an `xsl:output`'s settings layered over them. Only an
    /// explicit setting overrides; unspecified `xsl:output` attributes leave the
    /// caller's corresponding option untouched.
    func applying(_ output: PureXML.XSLT.Output) -> Self {
        var copy = self
        if let indent = output.indent { copy.prettyPrint = indent }
        if let omit = output.omitXMLDeclaration { copy.includeXMLDeclaration = !omit }
        if let encoding = output.encoding { copy.encodingName = encoding }
        if let version = output.version { copy.xmlVersion = version }
        if let standalone = output.standalone { copy.standalone = standalone }
        return copy
    }
}
