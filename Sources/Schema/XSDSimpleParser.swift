private typealias XSDNode = PureXML.Schema.XSDNode
private typealias SimpleType = PureXML.Schema.SimpleType
private typealias XSDContext = PureXML.Schema.XSDContext
private typealias BuiltinType = PureXML.Schema.BuiltinType
private typealias Facets = PureXML.Schema.Facets

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
            // `pattern` accumulates in groups: OR within a restriction step, AND
            // across derivation (libxml2 `xmlSchemaValidateFacets`). Drop the inherited
            // enumeration when this step declares its own.
            if XSDNode.elementChildren(restriction).contains(where: { XSDNode.localName($0) == "enumeration" }) {
                facets.enumeration = nil
            }
            applyFacets(restriction, into: &facets)
            for error in facetDefinitionErrors(restriction, base: baseType) + patternErrors(restriction) {
                context.facetFindingSink.add(error, at: restriction)
            }
            return SimpleType(base: baseType.base, facets: facets, variety: baseType.variety, isBuiltinList: baseType.isBuiltinList)
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
                guard facet.name?.namespaceURI == PureXML.Schema.XSDParser.xsdNamespace else { continue }
                let value = XSDNode.attribute(facet, "value") ?? ""
                do {
                    _ = try PureXML.Regex.Pattern(value)
                } catch let error as PureXML.Regex.RegexError where rejectsPattern(error) {
                    errors.append("pattern '\(value)' is not a valid regular expression: \(error)")
                } catch {
                    // A construct the engine merely under-supports on an otherwise-
                    // valid pattern (`.badQuantifier` for the lenient `{,m}` form,
                    // `.badEscape`/`.badClass`) is a valid XSD pattern, not a schema
                    // error. The empty pattern is valid and never throws.
                }
            }
            return errors
        }

        /// Whether a regex-compile failure is a genuine syntax error (so the schema
        /// is invalid), as opposed to an engine limitation on an otherwise-valid XSD
        /// pattern. Conservative: only the unambiguous structural errors reject.
        private static func rejectsPattern(_ error: PureXML.Regex.RegexError) -> Bool {
            switch error {
            case .unbalanced, .danglingQuantifier, .reversedRange, .emptyClass, .reversedQuantifier,
                 .incompleteEscape, .unterminatedClass, .unescapedClassBracket, .invalidProperty:
                true
            case .badQuantifier, .badEscape, .badClass:
                false
            }
        }

        /// Schema-validity findings for the constraining facets declared on one
        /// `restriction` (XSD Part 2 Datatypes 4.3): the length-family rules plus
        /// the value-bound rules, both limited to the facets declared on this step
        /// so an inherited facet is never flagged here.
        static func facetDefinitionErrors(_ restriction: XSDTree, base: SimpleType) -> [String] {
            var errors = countFacetErrors(restriction) + boundFacetErrors(restriction, base: base)
            errors += whiteSpaceRestrictionErrors(restriction, base: base)
            errors += facetRestrictionErrors(restriction, base: base)
            errors += facetApplicabilityErrors(restriction, base: base)
            return errors
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
            let baseFractionDigits = base.facets.fractionDigits ?? (base.base.derives(from: .integer) ? 0 : nil)
            if let baseFractionDigits, let localFractionDigits = localFacets.fractionDigits, localFractionDigits > baseFractionDigits {
                errors.append("facet 'fractionDigits' (\(localFractionDigits)) cannot be greater than base 'fractionDigits' (\(baseFractionDigits))")
            }
            return errors
        }

        private static func facetApplicabilityErrors(_ restriction: XSDTree, base: SimpleType) -> [String] {
            guard case .atomic = base.variety else { return [] }
            var errors: [String] = []
            let allowed = allowedFacets(for: base.base.primitive)
            let facetNames: Set = [
                "length", "minLength", "maxLength", "pattern", "enumeration", "whiteSpace",
                "maxInclusive", "maxExclusive", "minInclusive", "minExclusive", "totalDigits", "fractionDigits",
            ]
            for child in XSDNode.elementChildren(restriction) {
                guard child.name?.namespaceURI == PureXML.Schema.XSDParser.xsdNamespace else { continue }
                guard let name = XSDNode.localName(child), facetNames.contains(name) else { continue }
                if !allowed.contains(name) {
                    errors.append("facet '\(name)' does not apply to base type '\(base.base.rawValue)'")
                }
            }
            return errors
        }

        private static func allowedFacets(for primitive: Primitive) -> Set<String> {
            switch primitive {
            case .string, .anyURI, .hexBinary, .base64Binary, .name, .ncName, .nmtoken, .language, .qName, .notation:
                ["length", "minLength", "maxLength", "pattern", "enumeration", "whiteSpace"]
            case .boolean:
                ["pattern", "whiteSpace"]
            case .decimal, .integer:
                ["totalDigits", "fractionDigits", "pattern", "whiteSpace", "enumeration", "maxInclusive", "maxExclusive", "minInclusive", "minExclusive"]
            case .double, .float, .duration, .dateKind:
                ["pattern", "whiteSpace", "enumeration", "maxInclusive", "maxExclusive", "minInclusive", "minExclusive"]
            }
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
                guard facet.name?.namespaceURI == PureXML.Schema.XSDParser.xsdNamespace else { continue }
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
                guard facet.name?.namespaceURI == PureXML.Schema.XSDParser.xsdNamespace else { continue }
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
                guard facet.name?.namespaceURI == PureXML.Schema.XSDParser.xsdNamespace else { continue }
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
                  let high = bounds["maxInclusive"] ?? bounds["maxExclusive"]
            else { return [] }
            if case .duration = base.base.primitive {
                guard let lowDuration = DurationValue(low), let highDuration = DurationValue(high) else { return [] }
                let order = lowDuration.compare(to: highDuration)
                if order == .greaterThan {
                    return ["lower bound '\(low)' exceeds upper bound '\(high)'"]
                }
                let exclusive = bounds["minExclusive"] != nil || bounds["maxExclusive"] != nil
                if exclusive {
                    if order == .equal {
                        return ["bounds '\(low)' and '\(high)' describe an empty value space"]
                    }
                }
                return []
            }
            guard let lowValue = base.base.primitive.ordered(low),
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
    }
}
