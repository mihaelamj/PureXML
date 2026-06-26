/// One step of the iterative canonical serialization: a node to emit with its
/// in-scope and already-rendered namespace context, or a deferred element close.
enum CanonicalStep {
    case open(PureXML.Model.Node, inScope: [String: String], rendered: [String: String])
    case close(String)
}
