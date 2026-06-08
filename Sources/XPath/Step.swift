extension PureXML.XPath {
    /// One compiled location step: an axis, a node test, and zero or more
    /// predicate expressions applied in order.
    struct Step: Equatable, Sendable {
        let axis: Axis
        let test: NodeTest
        let predicates: [Expression]
    }
}
