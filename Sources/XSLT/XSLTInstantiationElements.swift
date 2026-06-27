// Element construction, template application, and node assembly for the iterative
// XSLT evaluator (see XSLTInstantiation.swift).

extension XSLTDriver {
    // MARK: Element construction

    /// The attributes an element carries before its body content: attribute sets
    /// (lowest precedence) then literal attributes.
    private func elementBaseAttributes(
        _ literalAttributes: [PureXML.XSLT.LiteralAttribute],
        _ useAttributeSets: [String],
        _ context: XSLTContext,
    ) -> [PureXML.Model.Attribute] {
        var attributes = transformer.attributeSetAttributes(useAttributeSets, context, visiting: [])
        attributes += literalAttributes.map { PureXML.Model.Attribute(name: $0.name, value: transformer.avt($0.value, context)) }
        return attributes
    }

    /// Pushes a finished element and its body, so the body fills a child
    /// accumulator that the finish step then wraps.
    private func pushElementBody(_ finish: Finish, _ body: [Instruction], _ context: XSLTContext, _ sink: Sink) {
        let child = Accumulator()
        stack.append(.finish(finish, child, sink.into))
        stack.append(.run(body, 0, context, Sink(depth: sink.depth, into: child)))
    }

    func pushLiteralElement(_ instruction: Instruction, _ context: XSLTContext, _ sink: Sink) {
        guard case let .literalElement(name, attributes, namespaces, useAttributeSets, body) = instruction else { return }
        let aliasedAttributes = attributes.map { PureXML.XSLT.LiteralAttribute(name: transformer.aliased($0.name), value: $0.value) }
        // The copied namespace nodes (7.1.1) travel as xmlns attributes; an
        // aliased stylesheet namespace declares its result namespace instead.
        var declarations: [PureXML.XSLT.LiteralAttribute] = []
        for (prefix, uri) in namespaces.sorted(by: { $0.key < $1.key }) {
            let alias = transformer.stylesheet.namespaceAliases[uri]
            let resolvedPrefix = prefix.isEmpty ? nil : prefix
            let resolvedURI = alias?.uri ?? uri
            let attributeName = resolvedPrefix.map { "xmlns:" + $0 } ?? "xmlns"
            declarations.append(PureXML.XSLT.LiteralAttribute(name: PureXML.Model.QualifiedName(attributeName), value: [.literal(resolvedURI)]))
        }
        let base = elementBaseAttributes(declarations + aliasedAttributes, useAttributeSets, context)
        pushElementBody(.element(transformer.aliased(name), base), body, context, sink)
    }

    func pushElement(_ instruction: Instruction, _ context: XSLTContext, _ sink: Sink) {
        guard case let .element(nameTemplate, namespaceTemplate, namespaces, useAttributeSets, body) = instruction else { return }
        let raw = transformer.avt(nameTemplate, context)
        let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
        let hasExplicitNamespace = (namespaceTemplate.map { !transformer.avt($0, context).isEmpty }) ?? false
        let prefix = parts.count == 2 ? String(parts[0]) : nil
        let undeclaredPrefix = !hasExplicitNamespace && (prefix.map { $0 != "xml" && namespaces[$0] == nil } ?? false)
        let unusableName = raw.isEmpty || parts.contains(where: \.isEmpty) || parts.count > 2
            || !parts.allSatisfy { PureXML.Parsing.XMLCharacter.isValidName(String($0)) } || undeclaredPrefix
        if unusableName {
            // The recovery emits the content without the wrapper element.
            pushElementBody(.filteredElement, body, context, sink)
            return
        }
        let name = transformer.createdName(nameTemplate, namespaceTemplate, namespaces, context, isAttribute: false)
        let base = elementBaseAttributes([], useAttributeSets, context)
        pushElementBody(.element(name, base), body, context, sink)
    }

    func pushCopy(_ useAttributeSets: [String], _ body: [Instruction], _ context: XSLTContext, _ sink: Sink) {
        // A non-tree current node copies itself.
        if let current = context.current {
            switch current {
            case let .attribute(_, attribute):
                sink.into.items.append(.attribute(attribute))
                return
            case let .namespace(_, prefix, uri):
                sink.into.items.append(.attribute(.init(prefix.isEmpty ? "xmlns" : "xmlns:" + prefix, uri)))
                return
            case .tree:
                break
            }
        }
        switch context.node.kind {
        case .element:
            let base = elementBaseAttributes(Host.namespaceDeclarations(inScopeAt: context.node), useAttributeSets, context)
            pushElementBody(.element(context.node.name ?? .init(""), base), body, context, sink)
        case .text, .cdata:
            sink.into.items.append(.node(.text(context.node.value)))
        case .comment:
            sink.into.items.append(.node(.comment(context.node.value)))
        case .processingInstruction:
            sink.into.items.append(.node(.processingInstruction(target: context.node.name?.description ?? "", data: context.node.value)))
        case .document:
            // The root copies to no element; use-attribute-sets join the enclosing
            // result element ahead of the copied content (7.5).
            let setAttributes = transformer.attributeSetAttributes(useAttributeSets, context, visiting: []).map(ResultItem.attribute)
            sink.into.items.append(contentsOf: setAttributes)
            stack.append(.run(body, 0, context, sink))
        default:
            stack.append(.run(body, 0, context, sink))
        }
    }

    // MARK: Template application

    func stepApplyTemplates(_ nodes: [PureXML.XPath.Node], _ application: Application) {
        // Reversed so the per-node work pops in document order; each node's own
        // sub-work then completes before the next node's pops.
        let size = nodes.count
        for (offset, xnode) in nodes.enumerated().reversed() {
            stack.append(.applyOne(xnode, offset + 1, size, application))
        }
    }

    func stepApplyOne(_ xnode: PureXML.XPath.Node, _ position: Int, _ size: Int, _ application: Application) {
        guard let owner = Host.ownerNode(xnode) else { return }
        let nodeContext = XSLTContext(
            node: owner,
            current: xnode.treeNode == nil ? xnode : nil,
            position: position,
            size: size,
            variables: application.caller.variables,
            mode: application.mode,
        )
        if let template = transformer.bestTemplate(for: xnode, mode: application.mode) {
            pushTemplateBody(template, nodeContext, application.parameters, application.caller, application.sink)
        } else {
            pushBuiltInRule(xnode, application.mode, nodeContext, application.sink)
        }
    }

    /// Binds a template's parameters and schedules its body (one deeper).
    func pushTemplateBody(
        _ template: PureXML.XSLT.Template,
        _ context: XSLTContext,
        _ parameters: [Binding],
        _ caller: XSLTContext,
        _ sink: Sink,
    ) {
        let depth = sink.depth + 1
        guard depth <= transformer.maxTemplateDepth else {
            transformer.recursionGuard.exceeded = true
            return
        }
        var context = context
        context.importPrecedence = template.importPrecedence
        context.importRangeLow = template.importRangeLow
        context.namespaces = template.namespaces
        context.baseURI = template.baseURI
        for parameter in template.parameters {
            if let passed = parameters.first(where: { $0.name == parameter.name }) {
                context.variables[parameter.name] = transformer.variableValue(passed.select, passed.body, caller)
            } else {
                context.variables[parameter.name] = transformer.variableValue(parameter.select, parameter.body, context)
            }
        }
        stack.append(.run(template.body, 0, context, Sink(depth: depth, into: sink.into)))
    }

    func pushBuiltInRule(_ xnode: PureXML.XPath.Node, _ mode: String?, _ context: XSLTContext, _ sink: Sink) {
        let depth = sink.depth + 1
        guard depth <= transformer.maxTemplateDepth else {
            transformer.recursionGuard.exceeded = true
            return
        }
        switch xnode {
        case let .tree(node):
            switch node.kind {
            case .element, .document:
                let application = Application(mode: mode, parameters: [], caller: context, sink: Sink(depth: depth, into: sink.into))
                stack.append(.applyTemplates(node.children.map { .tree($0) }, application))
            case .text, .cdata:
                sink.into.items.append(.node(.text(node.value)))
            default:
                break
            }
        case let .attribute(_, attribute):
            sink.into.items.append(.node(.text(attribute.value)))
        case let .namespace(_, _, uri):
            sink.into.items.append(.node(.text(uri)))
        }
    }

    func pushCallTemplate(_ name: String, _ parameters: [Binding], _ context: XSLTContext, _ sink: Sink) {
        // XSLT 1.0 section 6: the highest import-precedence definition wins.
        guard let template = transformer.stylesheet.templates.filter({ $0.name == name })
            .max(by: { $0.importPrecedence < $1.importPrecedence }) else { return }
        pushTemplateBody(template, context, parameters, context, sink)
    }

    func pushApplyImports(_ context: XSLTContext, _ sink: Sink) {
        if let template = transformer.bestTemplate(for: context.focus, mode: context.mode, below: context.importPrecedence, atLeast: context.importRangeLow) {
            pushTemplateBody(template, context, [], context, sink)
        } else {
            pushBuiltInRule(context.focus, context.mode, context, sink)
        }
    }

    // MARK: Finishing a node

    func stepFinish(_ kind: Finish, _ child: Accumulator, _ into: Accumulator) {
        switch kind {
        case let .element(name, baseAttributes):
            var attributes = baseAttributes
            var children: [PureXML.Model.Node] = []
            for item in child.items {
                switch item {
                case let .attribute(attribute):
                    // Ignored once content has been added (the recovery for an
                    // attribute created after children).
                    if children.isEmpty { attributes.append(attribute) }
                case let .node(node):
                    children.append(node)
                }
            }
            into.items.append(.node(.element(.init(name: name, attributes: Host.deduplicated(attributes), children: children))))
        case .filteredElement:
            into.items.append(contentsOf: child.items.filter { if case .attribute = $0 { false } else { true } })
        case .comment:
            into.items.append(.node(.comment(transformer.escapedTextValue(of: child.items))))
        case let .processingInstruction(target):
            into.items.append(.node(.processingInstruction(target: target, data: transformer.escapedTextValue(of: child.items))))
        case let .attribute(name):
            into.items.append(.attribute(.init(name: name, value: transformer.escapedTextValue(of: child.items))))
        }
    }
}
