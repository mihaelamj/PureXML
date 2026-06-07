extension PureXML.XPath {
    /// The supported XPath axes. The model is a value tree without parent
    /// pointers, so only the forward axes are available; upward axes (parent,
    /// ancestor) and sibling axes are intentionally out of scope.
    enum Axis: Equatable {
        /// Immediate children (the default axis).
        case child
        /// All descendants at any depth (reached with `//`).
        case descendant
        /// The context node itself (`.`).
        case selfNode
        /// Attributes of the context element (`@`).
        case attribute
    }
}
