// The step methods of the iterative XSLT evaluator (see XSLTInstantiation.swift).
// Each instruction either appends its produced items to the sink synchronously or
// pushes sub-work; the rest of the body is always pushed first so it pops last,
// keeping result-tree document order.

extension XSLTDriver {
    func stepRun(_ body: [Instruction], _ cursor: Int, _ context: XSLTContext, _ sink: Sink) {
        guard cursor < body.count else { return }
        let instruction = body[cursor]
        switch instruction {
        case let .variable(name, select, variableBody):
            // A variable binds for the rest of the body; thread the updated context.
            var context = context
            context.variables[name] = transformer.variableValue(select, variableBody, context)
            stack.append(.run(body, cursor + 1, context, sink))
            return
        case let .fallback(fallbackBody):
            stack.append(.run(body, cursor + 1, context, sink))
            stack.append(.run(fallbackBody, 0, context, sink))
            return
        default:
            break
        }
        // The remainder of the body runs after this instruction's items.
        stack.append(.run(body, cursor + 1, context, sink))
        if runSimple(instruction, context, sink) { return }
        if runControl(instruction, context, sink) { return }
        if runTemplate(instruction, context, sink) { return }
        runConstruct(instruction, context, sink)
    }

    private func runSimple(_ instruction: Instruction, _ context: XSLTContext, _ sink: Sink) -> Bool {
        switch instruction {
        case let .literalText(text):
            sink.into.items.append(.node(.text(text)))
        case let .valueOf(select, raw):
            let value = transformer.string(select, context)
            sink.into.items.append(.node(.text(raw ? PureXML.XSLT.RawText.marked(value) : value)))
        case .number:
            sink.into.items.append(.node(.text(transformer.numberInstruction(instruction, context))))
        case let .copyOf(select):
            sink.into.items.append(contentsOf: transformer.copyOf(select, context))
        case let .message(terminate, messageBody):
            if terminate, transformer.termination.message == nil {
                transformer.termination.message = Host.text(of: transformer.instantiate(messageBody, context))
            }
        default:
            return false
        }
        return true
    }

    private func runControl(_ instruction: Instruction, _ context: XSLTContext, _ sink: Sink) -> Bool {
        switch instruction {
        case let .ifInstruction(test, thenBody):
            if transformer.boolean(test, context) { stack.append(.run(thenBody, 0, context, sink)) }
        case let .choose(whens, otherwise):
            let branch = whens.first { transformer.boolean($0.test, context) }?.body ?? otherwise
            stack.append(.run(branch, 0, context, sink))
        case let .forEach(select, sorts, eachBody):
            pushForEach(select, sorts, eachBody, context, sink)
        default:
            return false
        }
        return true
    }

    private func runTemplate(_ instruction: Instruction, _ context: XSLTContext, _ sink: Sink) -> Bool {
        switch instruction {
        case let .applyTemplates(select, mode, sorts, parameters):
            let nodes = transformer.sorted(transformer.selectXPathNodes(select ?? "node()", context), sorts, context)
            stack.append(.applyTemplates(nodes, Application(mode: mode, parameters: parameters, caller: context, sink: sink)))
        case let .callTemplate(name, parameters):
            pushCallTemplate(name, parameters, context, sink)
        case .applyImports:
            pushApplyImports(context, sink)
        default:
            return false
        }
        return true
    }

    private func runConstruct(_ instruction: Instruction, _ context: XSLTContext, _ sink: Sink) {
        switch instruction {
        case .literalElement:
            pushLiteralElement(instruction, context, sink)
        case .element:
            pushElement(instruction, context, sink)
        case let .attribute(nameTemplate, namespaceTemplate, namespaces, attributeBody):
            let name = transformer.createdName(nameTemplate, namespaceTemplate, namespaces, context, isAttribute: true)
            pushTextNode(.attribute(name), attributeBody, context, sink)
        case let .copy(useAttributeSets, copyBody):
            pushCopy(useAttributeSets, copyBody, context, sink)
        case let .comment(commentBody):
            pushTextNode(.comment, commentBody, context, sink)
        case let .processingInstruction(nameTemplate, piBody):
            pushTextNode(.processingInstruction(transformer.avt(nameTemplate, context)), piBody, context, sink)
        default:
            break
        }
    }

    private func pushForEach(
        _ select: String,
        _ sorts: [PureXML.XSLT.Sort],
        _ body: [Instruction],
        _ context: XSLTContext,
        _ sink: Sink,
    ) {
        let nodes = transformer.sorted(transformer.selectXPathNodes(select, context), sorts, context)
        // Reversed so the nodes' bodies pop in document order into the sink.
        for (offset, xnode) in nodes.enumerated().reversed() {
            guard let owner = Host.ownerNode(xnode) else { continue }
            var itemContext = XSLTContext(
                node: owner,
                current: xnode.treeNode == nil ? xnode : nil,
                position: offset + 1,
                size: nodes.count,
                variables: context.variables,
            )
            itemContext.baseURI = context.baseURI
            stack.append(.run(body, 0, itemContext, sink))
        }
    }

    private func pushTextNode(_ kind: Finish, _ body: [Instruction], _ context: XSLTContext, _ sink: Sink) {
        let child = Accumulator()
        stack.append(.finish(kind, child, sink.into))
        stack.append(.run(body, 0, context, Sink(depth: sink.depth, into: child)))
    }
}
