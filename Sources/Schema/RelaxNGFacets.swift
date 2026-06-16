extension PureXML.Schema {
    /// Builds the XSD-style ``Facets`` a RELAX NG datatype constrains its base type
    /// with, from `<param name= >value` pairs (XML syntax) or `name "value"` pairs
    /// (compact syntax). Shared by both RELAX NG parsers.
    enum RelaxNGFacets {
        static func apply(_ name: String, _ value: String, into facets: inout Facets) {
            applyValue(name, value, into: &facets)
            applyNumeric(name, Int(value), into: &facets)
        }

        private static func applyValue(_ name: String, _ value: String, into facets: inout Facets) {
            switch name {
            case "pattern": facets.patternGroups.append([value])
            case "minInclusive": facets.minInclusive = value
            case "maxInclusive": facets.maxInclusive = value
            case "minExclusive": facets.minExclusive = value
            case "maxExclusive": facets.maxExclusive = value
            default: break
            }
        }

        private static func applyNumeric(_ name: String, _ number: Int?, into facets: inout Facets) {
            switch name {
            case "length": facets.length = number
            case "minLength": facets.minLength = number
            case "maxLength": facets.maxLength = number
            case "totalDigits": facets.totalDigits = number
            case "fractionDigits": facets.fractionDigits = number
            default: break
            }
        }
    }
}
