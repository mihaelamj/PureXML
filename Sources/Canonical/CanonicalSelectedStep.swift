/// One step of the iterative canonical node-subset serialization (C14N over a
/// selected subtree): a `TreeNode` to emit with its in-scope and already-rendered
/// namespace context, or a deferred element close. The mutable-tree counterpart
/// to ``CanonicalStep``.
enum CanonicalSelectedStep {
    case open(PureXML.Model.TreeNode, inScope: [String: String], rendered: [String: String])
    case close(String)
}
