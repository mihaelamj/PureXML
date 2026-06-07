extension PureXML.XPath {
    /// One compiled location step: an axis, a node test, and zero or more
    /// predicates applied in order.
    struct Step: Equatable {
        let axis: Axis
        let test: NodeTest
        let predicates: [Predicate]
    }
}
