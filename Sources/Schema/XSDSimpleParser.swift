extension PureXML.Schema {
    /// Parses XSD simple types: atomic restrictions with the full facet set, and
    /// the `list` and `union` varieties. Kept beside ``XSDParser``, sharing its
    /// module-scope tree helpers and parsing context.
    enum XSDSimpleParser {
        static func simpleType(_ node: XSDTree, _ context: XSDContext) -> SimpleType {
            if let list = XSDNode.firstChild(node, named: "list") {
                return listType(list, context)
            }
            if let union = XSDNode.firstChild(node, named: "union") {
                return unionType(union, context)
            }
            guard let restriction = XSDNode.firstChild(node, named: "restriction") else {
                return SimpleType(base: .string)
            }
            // Resolve the base through simpleTypeReference so the built-in list
            // datatypes (NMTOKENS, IDREFS, ENTITIES) keep their list variety: a
            // length facet on one of them counts list items, not characters (#146).
            // Restricting a user type inherits its base, facets, and variety. When the
            // `base` attribute is absent the base is the inline `<simpleType>` child
            // (an anonymous base); resolving it likewise preserves its list/union
            // variety, so a length facet over an inline list base counts items.
            let baseType: SimpleType = if let baseName = XSDNode.attribute(restriction, "base") {
                simpleTypeReference(baseName, context)
            } else if let inlineBase = XSDNode.firstChild(restriction, named: "simpleType") {
                simpleType(inlineBase, context)
            } else {
                SimpleType(base: .string)
            }
            var facets = baseType.facets
            // A restriction's own `enumeration` replaces the inherited set (the new
            // enumeration is the value space, not a union with the base's), whereas
            // `pattern` accumulates across steps and is ANDed. So drop the inherited
            // enumeration when this step declares its own.
            if XSDNode.elementChildren(restriction).contains(where: { XSDNode.localName($0) == "enumeration" }) {
                facets.enumeration = nil
            }
            applyFacets(restriction, into: &facets)
            for error in facetDefinitionErrors(restriction, base: baseType) + patternErrors(restriction) {
                context.diagnostics.report(error)
            }
            return SimpleType(base: baseType.base, facets: facets, variety: baseType.variety)
        }

        /// Schema-validity findings for the `pattern` facets declared on one
        /// `restriction`: each `pattern` value must be a valid XSD regular
        /// expression. The pattern was only compiled lazily at instance time
        /// (`try?`), so an unparseable one was silently ignored and the schema
        /// accepted. Only the unambiguous structural errors reject (a quantifier
        /// with nothing to repeat, `?a`; unbalanced parentheses, `((a)`); see
        /// `rejectsPattern`.
        static func patternErrors(_ restriction: XSDTree) -> [String] {
            var errors: [String] = []
            for facet in XSDNode.elementChildren(restriction) where XSDNode.localName(facet) == "pattern" {
                let value = XSDNode.attribute(facet, "value") ?? ""
                do {
                    _ = try PureXML.Regex.Pattern(value)
                } catch let error as PureXML.Regex.RegexError where rejectsPattern(error) {
                    errors.append("pattern '\(value)' is not a valid regular expression: \(error)")
                } catch {
                    // A construct the engine does not support (`.empty`, `.unsupported`
                    // for an untabulated `\p{Is...}` block, `.badQuantifier` for the
                    // lenient `{,m}` form) is a valid XSD pattern, not a schema error.
                }
            }
            return errors
        }

        /// Whether a regex-compile failure is a genuine syntax error (so the schema
        /// is invalid), as opposed to an engine limitation on an otherwise-valid XSD
        /// pattern. Conservative: only the unambiguous structural errors reject.
        private static func rejectsPattern(_ error: PureXML.Regex.RegexError) -> Bool {
            switch error {
            case .unbalanced, .danglingQuantifier:
                true
            case .empty, .unsupported, .badQuantifier, .badEscape, .badClass:
                false
            }
        }

        /// Schema-validity findings for the constraining facets declared on one
        /// `restriction` (XSD Part 2 Datatypes 4.3): the length-family rules plus
        /// the value-bound rules, both limited to the facets declared on this step
        /// so an inherited facet is never flagged here.
        static func facetDefinitionErrors(_ restriction: XSDTree, base: SimpleType) -> [String] {
            countFacetErrors(restriction) + boundFacetErrors(restriction, base: base)
                + whiteSpaceRestrictionErrors(restriction, base: base)
                + facetRestrictionErrors(restriction, base: base)
        }

        /// The `length`, `minLength`, `maxLength`, `totalDigits`, and `fractionDigits`
        /// facets on a restriction must restrict or equal the base type's facets.
        private static func facetRestrictionErrors(_ restriction: XSDTree, base: SimpleType) -> [String] {
            var errors: [String] = []
            var localFacets = Facets()
            applyFacets(restriction, into: &localFacets)
            if let baseLength = base.facets.length, let localLength = localFacets.length, localLength != baseLength {
                errors.append("facet 'length' (\(localLength)) must equal base 'length' (\(baseLength))")
            }
            if let baseMinLength = base.facets.minLength, let localMinLength = localFacets.minLength, localMinLength < baseMinLength {
                errors.append("facet 'minLength' (\(localMinLength)) cannot be less than base 'minLength' (\(baseMinLength))")
            }
            if let baseMaxLength = base.facets.maxLength, let localMaxLength = localFacets.maxLength, localMaxLength > baseMaxLength {
                errors.append("facet 'maxLength' (\(localMaxLength)) cannot be greater than base 'maxLength' (\(baseMaxLength))")
            }
            if let baseTotalDigits = base.facets.totalDigits, let localTotalDigits = localFacets.totalDigits, localTotalDigits > baseTotalDigits {
                errors.append("facet 'totalDigits' (\(localTotalDigits)) cannot be greater than base 'totalDigits' (\(baseTotalDigits))")
            }
            if let baseFractionDigits = base.facets.fractionDigits, let localFractionDigits = localFacets.fractionDigits, localFractionDigits > baseFractionDigits {
                errors.append("facet 'fractionDigits' (\(localFractionDigits)) cannot be greater than base 'fractionDigits' (\(baseFractionDigits))")
            }
            return errors
        }

        /// The `whiteSpace` facet may only strengthen, never relax, the base type's
        /// effective whiteSpace (XSD Part 2 §4.3.6, the facet's valid-restriction
        /// rule): the order is `preserve` < `replace` < `collapse`, so a base fixed
        /// to `collapse` admits only `collapse`, and a base of `replace` admits
        /// `replace` or `collapse`. Checked for an atomic base only; the base's
        /// effective whiteSpace is its own facet, falling back to its built-in
        /// intrinsic. If the base type has not resolved its own whiteSpace the check
        /// can only under-detect, never reject a valid restriction.
        private static func whiteSpaceRestrictionErrors(_ restriction: XSDTree, base: SimpleType) -> [String] {
            guard case .atomic = base.variety, let declared = declaredWhiteSpace(restriction) else { return [] }
            let baseWhiteSpace = base.facets.whiteSpace ?? base.base.whiteSpace
            guard whiteSpaceStrength(declared) < whiteSpaceStrength(baseWhiteSpace) else { return [] }
            return ["whiteSpace '\(whiteSpaceName(declared))' may not relax the base type's whiteSpace '\(whiteSpaceName(baseWhiteSpace))'"]
        }

        private static func declaredWhiteSpace(_ restriction: XSDTree) -> WhiteSpace? {
            for facet in XSDNode.elementChildren(restriction) where XSDNode.localName(facet) == "whiteSpace" {
                return whiteSpace(XSDNode.attribute(facet, "value"))
            }
            return nil
        }

        private static func whiteSpaceStrength(_ whiteSpace: WhiteSpace) -> Int {
            switch whiteSpace {
            case .preserve: 0
            case .replace: 1
            case .collapse: 2
            }
        }

        private static func whiteSpaceName(_ whiteSpace: WhiteSpace) -> String {
            switch whiteSpace {
            case .preserve: "preserve"
            case .replace: "replace"
            case .collapse: "collapse"
            }
        }

        /// Length-family findings: `length`, `minLength`, `maxLength`,
        /// `totalDigits`, and `fractionDigits` must be `nonNegativeInteger`
        /// (`totalDigits` a `positiveInteger`), `length` may not co-occur with
        /// `minLength`/`maxLength`, and `minLength` <= `maxLength`,
        /// `fractionDigits` <= `totalDigits`. Reads the raw lexical, since numeric
        /// facet parsing silently drops a malformed value.
        private static func countFacetErrors(_ restriction: XSDTree) -> [String] {
            var errors: [String] = []
            var values: [String: String] = [:] // facet name -> canonical digit string
            let countFacets: Set = ["length", "minLength", "maxLength", "totalDigits", "fractionDigits"]
            for facet in XSDNode.elementChildren(restriction) {
                guard let name = XSDNode.localName(facet), countFacets.contains(name) else { continue }
                let raw = XSDNode.attribute(facet, "value")
                guard let canonical = raw.flatMap(canonicalNonNegativeInteger) else {
                    errors.append("facet '\(name)' value '\(raw ?? "")' is not a valid nonNegativeInteger")
                    continue
                }
                if name == "totalDigits", canonical == "0" {
                    errors.append("facet 'totalDigits' value '\(raw ?? "")' must be a positiveInteger")
                }
                values[name] = canonical
            }
            if values["length"] != nil, values["minLength"] != nil {
                errors.append("facets 'length' and 'minLength' may not both be specified")
            }
            if values["length"] != nil, values["maxLength"] != nil {
                errors.append("facets 'length' and 'maxLength' may not both be specified")
            }
            if let low = values["minLength"], let high = values["maxLength"], greater(low, than: high) {
                errors.append("facet 'minLength' (\(low)) exceeds 'maxLength' (\(high))")
            }
            if let fraction = values["fractionDigits"], let total = values["totalDigits"], greater(fraction, than: total) {
                errors.append("facet 'fractionDigits' (\(fraction)) exceeds 'totalDigits' (\(total))")
            }
            return errors
        }

        /// Value-bound findings: each `minInclusive`/`maxInclusive`/`minExclusive`/
        /// `maxExclusive` and `enumeration` value must be a valid value of the base
        /// type; `minInclusive` excludes `minExclusive` and `maxInclusive` excludes
        /// `maxExclusive`; and the lower bound may not exceed the upper bound (nor
        /// equal it when either side is exclusive, which is an empty value space).
        /// Ordering is compared in the base primitive's value space.
        private static func boundFacetErrors(_ restriction: XSDTree, base: SimpleType) -> [String] {
            var errors: [String] = []
            var bounds: [String: String] = [:]
            for facet in XSDNode.elementChildren(restriction) {
                guard let name = XSDNode.localName(facet) else { continue }
                let raw = XSDNode.attribute(facet, "value") ?? ""
                switch name {
                case "minInclusive", "maxInclusive", "minExclusive", "maxExclusive":
                    if base.validate(raw) != nil {
                        errors.append("facet '\(name)' value '\(raw)' is not a valid value of the base type")
                    } else {
                        bounds[name] = raw
                    }
                case "enumeration":
                    if base.validate(raw) != nil {
                        errors.append("enumeration value '\(raw)' is not a valid value of the base type")
                    }
                default:
                    break
                }
            }
            if bounds["minInclusive"] != nil, bounds["minExclusive"] != nil {
                errors.append("facets 'minInclusive' and 'minExclusive' may not both be specified")
            }
            if bounds["maxInclusive"] != nil, bounds["maxExclusive"] != nil {
                errors.append("facets 'maxInclusive' and 'maxExclusive' may not both be specified")
            }
            errors += boundOrderErrors(bounds, base: base)
            return errors
        }

        /// The lower-versus-upper-bound ordering finding, if any, comparing in the
        /// base primitive's value space. Skipped for an unordered primitive (the
        /// `ordered` lookup returns nil), so only a defined order is checked.
        private static func boundOrderErrors(_ bounds: [String: String], base: SimpleType) -> [String] {
            guard let low = bounds["minInclusive"] ?? bounds["minExclusive"],
                  let high = bounds["maxInclusive"] ?? bounds["maxExclusive"],
                  let lowValue = base.base.primitive.ordered(low),
                  let highValue = base.base.primitive.ordered(high)
            else { return [] }
            if lowValue > highValue {
                return ["lower bound '\(low)' exceeds upper bound '\(high)'"]
            }
            let exclusive = bounds["minExclusive"] != nil || bounds["maxExclusive"] != nil
            if lowValue == highValue, exclusive {
                return ["bounds '\(low)' and '\(high)' describe an empty value space"]
            }
            return []
        }

        /// The canonical digit string of a lexical `nonNegativeInteger` (optional
        /// leading `+`, ASCII digits, surrounding whitespace tolerated), with the
        /// sign and leading zeros stripped (`"0"` for zero), or nil when the lexical
        /// is not one (`-1`, ``, `a`, `1e2`). Independent of machine-integer range,
        /// so a huge but well-formed value is canonicalized, not misreported as
        /// malformed; the canonical form orders two values by length then lexically.
        private static func canonicalNonNegativeInteger(_ lexical: String) -> String? {
            var digits = Substring(lexical.trimmingXMLWhitespace())
            if digits.first == "+" { digits = digits.dropFirst() }
            guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            let trimmed = digits.drop { $0 == "0" }
            return trimmed.isEmpty ? "0" : String(trimmed)
        }

        /// Whether canonical nonNegativeInteger `lhs` is greater than `rhs`: a longer
        /// digit string is larger, and same-length strings compare lexicographically.
        private static func greater(_ lhs: String, than rhs: String) -> Bool {
            lhs.count != rhs.count ? lhs.count > rhs.count : lhs > rhs
        }

        static func simpleTypeReference(_ typeName: String, _ context: XSDContext) -> SimpleType {
            let local = XSDNode.stripPrefix(typeName)
            if let builtin = BuiltinType(rawValue: local) { return SimpleType(base: builtin) }
            if let item = listBuiltinItem(local) { return .list(item: SimpleType(base: item)) }
            return context.simpleTypes[local] ?? SimpleType(base: .string)
        }

        /// The item type of a built-in list datatype (`IDREFS`, `ENTITIES`,
        /// `NMTOKENS`), each a whitespace-separated list of its singular form.
        static func listBuiltinItem(_ name: String) -> BuiltinType? {
            switch name {
            case "IDREFS": .idref
            case "ENTITIES": .entity
            case "NMTOKENS": .nmtoken
            default: nil
            }
        }

        static func applyFacets(_ restriction: XSDTree, into facets: inout Facets) {
            for facet in XSDNode.elementChildren(restriction) {
                let value = XSDNode.attribute(facet, "value")
                applyStringFacet(XSDNode.localName(facet), value, into: &facets)
                applyNumericFacet(XSDNode.localName(facet), value, into: &facets)
            }
        }

        private static func listType(_ node: XSDTree, _ context: XSDContext) -> SimpleType {
            let item: SimpleType = if let itemType = XSDNode.attribute(node, "itemType") {
                simpleTypeReference(itemType, context)
            } else if let inline = XSDNode.firstChild(node, named: "simpleType") {
                simpleType(inline, context)
            } else {
                SimpleType(base: .string)
            }
            return .list(item: item)
        }

        private static func unionType(_ node: XSDTree, _ context: XSDContext) -> SimpleType {
            var members: [SimpleType] = []
            if let names = XSDNode.attribute(node, "memberTypes") {
                members += names.split(whereSeparator: \.isWhitespace).map { simpleTypeReference(String($0), context) }
            }
            members += XSDNode.children(node, named: "simpleType").map { simpleType($0, context) }
            return .union(members)
        }
    }
}

extension PureXML.Schema.XSDSimpleParser {
    private static func applyStringFacet(_ name: String?, _ value: String?, into facets: inout PureXML.Schema.Facets) {
        switch name {
        case "pattern": if let value { facets.patterns.append(value) }
        case "enumeration": if let value { facets.enumeration = (facets.enumeration ?? []) + [value] }
        case "minInclusive": facets.minInclusive = value
        case "maxInclusive": facets.maxInclusive = value
        case "minExclusive": facets.minExclusive = value
        case "maxExclusive": facets.maxExclusive = value
        case "whiteSpace": facets.whiteSpace = whiteSpace(value)
        default: break
        }
    }

    private static func applyNumericFacet(_ name: String?, _ value: String?, into facets: inout PureXML.Schema.Facets) {
        let number = value.flatMap(Int.init)
        switch name {
        case "length": facets.length = number
        case "minLength": facets.minLength = number
        case "maxLength": facets.maxLength = number
        case "totalDigits": facets.totalDigits = number
        case "fractionDigits": facets.fractionDigits = number
        default: break
        }
    }

    private static func whiteSpace(_ value: String?) -> PureXML.Schema.WhiteSpace? {
        switch value {
        case "preserve": .preserve
        case "replace": .replace
        case "collapse": .collapse
        default: nil
        }
    }
}
