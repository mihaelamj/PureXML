extension PureXML.XSLT {
    /// The XSLT `format-number` function over the default decimal format. Supports
    /// `0`/`#` digit places, `.` for the decimal point, `,` grouping, and a `%`
    /// percent suffix. Pure Swift, no Foundation.
    enum FormatNumber {
        static func format(_ value: Double, _ picture: String) -> String {
            guard !value.isNaN else { return "NaN" }
            guard !picture.isEmpty else { return PureXML.XPath.Value.format(value) }
            let percent = picture.contains("%")
            let pattern = picture.filter { $0 != "%" }
            let parts = pattern.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            let integerPattern = String(parts.first ?? "")
            let fractionPattern = parts.count > 1 ? String(parts[1]) : ""

            let minInteger = integerPattern.count(where: { $0 == "0" })
            let minFraction = fractionPattern.count(where: { $0 == "0" })
            let maxFraction = fractionPattern.count(where: { $0 == "0" || $0 == "#" })
            let grouping = integerPattern.contains(",")

            var magnitude = Swift.abs(percent ? value * 100 : value)
            magnitude = round(magnitude, places: maxFraction)
            let rendered = render(
                magnitude,
                minInteger: minInteger,
                minFraction: minFraction,
                maxFraction: maxFraction,
                grouping: grouping,
            )
            return (value < 0 ? "-" : "") + rendered + (percent ? "%" : "")
        }

        private static func round(_ value: Double, places: Int) -> Double {
            var scale = 1.0
            for _ in 0 ..< places {
                scale *= 10
            }
            return (value * scale).rounded() / scale
        }

        private static func render(
            _ value: Double,
            minInteger: Int,
            minFraction: Int,
            maxFraction: Int,
            grouping: Bool,
        ) -> String {
            let integerValue = Int(value)
            var integerText = String(integerValue)
            while integerText.count < Swift.max(1, minInteger) {
                integerText = "0" + integerText
            }
            if grouping { integerText = group(integerText) }

            var fractionValue = value - Double(integerValue)
            var fractionText = ""
            for _ in 0 ..< maxFraction {
                fractionValue *= 10
                let digit = Int(fractionValue)
                fractionText += String(digit)
                fractionValue -= Double(digit)
            }
            while fractionText.count > minFraction, fractionText.hasSuffix("0") {
                fractionText.removeLast()
            }
            return fractionText.isEmpty ? integerText : integerText + "." + fractionText
        }

        private static func group(_ digits: String) -> String {
            var result = ""
            for (offset, character) in digits.reversed().enumerated() {
                if offset > 0, offset.isMultiple(of: 3) { result.append(",") }
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
        ) -> PureXML.XPath.FunctionTable {
            PureXML.XPath.FunctionTable()
                .adding("current") { _, _ in .nodeSet([.tree(current)]) }
                .adding("format-number") { arguments, _ in
                    .string(FormatNumber.format(
                        arguments.first?.number ?? .nan,
                        arguments.count > 1 ? arguments[1].string : "",
                    ))
                }
                .adding("key") { arguments, _ in
                    let name = arguments.first?.string ?? ""
                    let value = arguments.count > 1 ? arguments[1].string : ""
                    return .nodeSet((keys[name]?[value] ?? []).map { .tree($0) })
                }
                .adding("document") { arguments, _ in
                    guard let uri = arguments.first?.string, let text = loader(uri),
                          let parsed = try? PureXML.parseTree(text) else { return .nodeSet([]) }
                    return .nodeSet([.tree(parsed)])
                }
        }

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

    /// The `xsl:number` numbering machinery: a node's position rendered per a
    /// format token (`1` arabic, `A`/`a` alphabetic, `I`/`i` roman).
    enum Numbering {
        /// The number for `node`: its 1-based position among preceding siblings of
        /// the same name (or the `count` name), rendered per `format`.
        static func value(of node: PureXML.Model.TreeNode, count: String?, format: String) -> String {
            let target = count ?? node.name?.localName
            var position = 1
            if let parent = node.parent {
                for sibling in parent.children {
                    if sibling === node { break }
                    if sibling.kind == .element, sibling.name?.localName == target { position += 1 }
                }
            }
            return render(position, format)
        }

        private static func render(_ number: Int, _ format: String) -> String {
            switch format.first {
            case "A": alphabetic(number, base: 65)
            case "a": alphabetic(number, base: 97)
            case "I": roman(number).uppercased()
            case "i": roman(number)
            default: String(number)
            }
        }

        private static func alphabetic(_ number: Int, base: UInt32) -> String {
            var value = number
            var result = ""
            while value > 0 {
                let remainder = UInt32((value - 1) % 26)
                if let scalar = Unicode.Scalar(base + remainder) {
                    result = String(Character(scalar)) + result
                }
                value = (value - 1) / 26
            }
            return result
        }

        private static func roman(_ number: Int) -> String {
            let table: [(Int, String)] = [
                (1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"), (90, "xc"),
                (50, "l"), (40, "xl"), (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i"),
            ]
            var value = number
            var result = ""
            for (amount, numeral) in table {
                while value >= amount {
                    result += numeral
                    value -= amount
                }
            }
            return result
        }
    }
}
