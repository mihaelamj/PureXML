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

        /// Whether the axis, taken from a SINGLE context node, yields its nodes
        /// already in document order with no duplicates, so a one-step path over
        /// it needs neither the de-duplication nor the document-order sort. True
        /// for the structural forward axes, which `AxisNavigation` produces in
        /// document order (child by child-array order, descendant by pre-order,
        /// the following families by document position). The attribute axis is
        /// excluded because its order interleaves with namespace declarations,
        /// and the namespace axis because its nodes are produced in dictionary
        /// (hash) order; the sort normalizes both, so they are left to it.
        var preservesDocumentOrderFromSingleContext: Bool {
            switch self {
            case .child, .descendant, .descendantOrSelf, .selfAxis, .followingSibling, .following: true
            default: false
            }
        }

        /// Whether the axis yields disjoint node-sets from distinct context nodes,
        /// so accumulating its results across a step's context nodes can never
        /// produce a duplicate and needs no cross-context de-duplication. A child,
        /// attribute, or namespace node belongs to exactly one element, and the
        /// self axis maps each distinct context to itself; every other axis
        /// (descendant, ancestor, the siblings, following/preceding, parent) can
        /// reach one node from two different contexts.
        var yieldsDisjointResults: Bool {
            switch self {
            case .child, .attribute, .namespace, .selfAxis: true
            default: false
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
