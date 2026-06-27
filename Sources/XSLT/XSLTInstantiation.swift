// The XSLT sequence-constructor evaluator, driven by an explicit work stack so
// template recursion and result-tree nesting do not consume the native stack.
// A recursive named template, an identity transform of a deeply-nested source,
// or any deep result tree is evaluated iteratively here; only stylesheet-bounded
// helper evaluation (a variable's or parameter's result-tree fragment, an
// attribute set, an xsl:message body) re-enters through a nested driver call,
// whose depth is bounded by the stylesheet's own nesting.
//
// A work item's `depth` is the logical template-application nesting (one per
// apply-templates / call-template / built-in-rule descent), not a native frame
// count. `maxTemplateDepth` caps it as runaway protection (an unbounded result
// tree would otherwise exhaust memory), failing gracefully via `recursionGuard`.

extension PureXML.XSLT.Transformer {
    /// Instantiates a sequence constructor, iteratively.
    func instantiate(_ body: [PureXML.XSLT.Instruction], _ context: XSLTContext) -> [ResultItem] {
        XSLTDriver(self).run(body, context)
    }

    /// Applies templates to `nodes` (already selected and sorted), iteratively.
    func applyTemplates(
        to nodes: [PureXML.XPath.Node],
        mode: String?,
        parameters: [PureXML.XSLT.Binding],
        _ context: XSLTContext,
    ) -> [ResultItem] {
        XSLTDriver(self).applyTemplates(nodes, mode: mode, parameters: parameters, context)
    }
}

/// The iterative evaluator. One per top-level `instantiate`/`applyTemplates`
/// call; nested helper evaluation makes its own. Holds the work stack so the step
/// methods need not thread it as a parameter.
final class XSLTDriver {
    typealias Host = PureXML.XSLT.Transformer
    typealias Instruction = PureXML.XSLT.Instruction
    typealias Binding = PureXML.XSLT.Binding

    /// A mutable, ordered bag of produced items a branch's work appends into; a
    /// deferred `finish` step assembles the parent node from it.
    final class Accumulator {
        var items: [ResultItem] = []
    }

    /// Where produced items go and at what logical recursion depth.
    struct Sink {
        let depth: Int
        let into: Accumulator
    }

    /// The shared context of one template application across its node-set: the
    /// mode, the parameters passed, the caller's context, and the sink.
    struct Application {
        let mode: String?
        let parameters: [Binding]
        let caller: XSLTContext
        let sink: Sink
    }

    /// How a completed child accumulator is turned into a node appended to a parent.
    enum Finish {
        /// Partition the child items into attributes (before the first node) and
        /// children, then wrap them in an element with the precomputed name and
        /// base attributes (attribute sets plus literal attributes).
        case element(PureXML.Model.QualifiedName, [PureXML.Model.Attribute])
        /// The `xsl:element` recovery for an unusable name: emit the content with
        /// no wrapper, dropping attribute items (XSLT 1.0 7.1.2).
        case filteredElement
        case comment
        case processingInstruction(String)
        case attribute(PureXML.Model.QualifiedName)
    }

    /// One unit of evaluation work.
    enum Work {
        /// Run `body` from `cursor` in `context`, appending to the sink.
        case run([Instruction], Int, XSLTContext, Sink)
        /// Apply templates to already-selected, already-sorted `nodes`.
        case applyTemplates([PureXML.XPath.Node], Application)
        /// Apply templates to one node (its position and size fixed). Each node is
        /// its own deferred work item so a leaf node's text and a nested node's
        /// template output land in the sink in document order.
        case applyOne(PureXML.XPath.Node, Int, Int, Application)
        /// Assemble a node from a finished child accumulator into a parent.
        case finish(Finish, Accumulator, Accumulator)
    }

    let transformer: Host
    var stack: [Work] = []

    init(_ transformer: Host) {
        self.transformer = transformer
    }

    func run(_ body: [Instruction], _ context: XSLTContext) -> [ResultItem] {
        let root = Accumulator()
        stack = [.run(body, 0, context, Sink(depth: 0, into: root))]
        drive()
        return root.items
    }

    func applyTemplates(
        _ nodes: [PureXML.XPath.Node],
        mode: String?,
        parameters: [Binding],
        _ context: XSLTContext,
    ) -> [ResultItem] {
        let root = Accumulator()
        let application = Application(mode: mode, parameters: parameters, caller: context, sink: Sink(depth: 0, into: root))
        stack = [.applyTemplates(nodes, application)]
        drive()
        return root.items
    }

    private func drive() {
        while let work = stack.popLast() {
            if transformer.termination.message != nil || transformer.recursionGuard.exceeded { continue }
            switch work {
            case let .run(body, cursor, context, sink):
                stepRun(body, cursor, context, sink)
            case let .applyTemplates(nodes, application):
                stepApplyTemplates(nodes, application)
            case let .applyOne(xnode, position, size, application):
                stepApplyOne(xnode, position, size, application)
            case let .finish(kind, child, into):
                stepFinish(kind, child, into)
            }
        }
    }
}
