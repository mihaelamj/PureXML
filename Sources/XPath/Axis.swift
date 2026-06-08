extension PureXML.XPath {
    /// The thirteen XPath 1.0 axes. Every axis is reachable now that the tree is
    /// parent-aware, so upward and sibling navigation are first-class.
    enum Axis: Equatable {
        case child
        case descendant
        case parent
        case ancestor
        case followingSibling
        case precedingSibling
        case following
        case preceding
        case attribute
        case namespace
        case selfAxis
        case descendantOrSelf
        case ancestorOrSelf

        /// Whether the axis is a reverse axis (its nodes are numbered in reverse
        /// document order for positional predicates).
        var isReverse: Bool {
            switch self {
            case .parent, .ancestor, .precedingSibling, .preceding, .ancestorOrSelf:
                true
            default:
                false
            }
        }

        /// The principal node kind of the axis: attributes for the attribute axis,
        /// namespaces for the namespace axis, elements otherwise. Governs what a
        /// name test or `*` selects.
        var principalKind: PrincipalKind {
            switch self {
            case .attribute: .attribute
            case .namespace: .namespace
            default: .element
            }
        }
    }

    /// The principal node kind selected by name tests on an axis.
    enum PrincipalKind: Equatable {
        case element
        case attribute
        case namespace
    }
}
