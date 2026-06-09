/// The transformer's runtime types are defined in XSLTRuntime.swift (nested in
/// the namespace); these file-private aliases keep them unqualified here.
private typealias ResultItem = PureXML.XSLT.ResultItem
private typealias XSLTContext = PureXML.XSLT.XSLTContext
private typealias Termination = PureXML.XSLT.Termination

extension PureXML.XSLT {
    /// Runs a compiled stylesheet against a source tree, producing a result tree
    /// by the XSLT 1.0 processing model: apply templates from the root, match each
    /// node to the highest-priority template (or the built-in rules), and
    /// instantiate the matched template's sequence constructor.
    struct Transformer {
        let stylesheet: Stylesheet
        let root: PureXML.Model.TreeNode
        let documentLoader: (String) -> String?
        private let keyIndex: PureXML.XSLT.KeyIndex
        private let termination = Termination()

        /// The `xsl:message terminate="yes"` text, if one fired during `run()`.
        var terminationMessage: String? {
            termination.message
        }

        init(stylesheet: Stylesheet, root: PureXML.Model.TreeNode, documentLoader: @escaping (String) -> String? = { _ in nil }) {
            self.stylesheet = stylesheet
            self.root = root
            self.documentLoader = documentLoader
            keyIndex = PureXML.XSLT.Library.buildKeyIndex(stylesheet: stylesheet, root: root)
        }

        func run() -> PureXML.Model.Node {
            var variables: [String: PureXML.XPath.Value] = [:]
            let baseContext = XSLTContext(node: root, position: 1, size: 1, variables: variables)
            for global in stylesheet.globals {
                if case let .variable(name, select, body) = global {
                    variables[name] = variableValue(select, body, baseContext)
                }
            }
            let context = XSLTContext(node: root, position: 1, size: 1, variables: variables)
            return .document(applyTemplates(to: [root], mode: nil, parameters: [], context).compactMap(Self.nodeOf))
        }

        fileprivate func bestTemplate(for node: PureXML.Model.TreeNode, mode: String?, below ceiling: Int = .max) -> Template? {
            stylesheet.templates.enumerated()
                .filter { $0.element.mode == mode && $0.element.importPrecedence < ceiling && ($0.element.match.map { matches(node, $0) } ?? false) }
                .max { lhs, rhs in
                    (lhs.element.importPrecedence, lhs.element.priority, lhs.offset)
                        < (rhs.element.importPrecedence, rhs.element.priority, rhs.offset)
                }?
                .element
        }

        private func matches(_ node: PureXML.Model.TreeNode, _ pattern: String) -> Bool {
            for branch in pattern.split(separator: "|") {
                let trimmed = branch.trimmingXMLWhitespace()
                let path = trimmed.hasPrefix("/") ? trimmed : "//" + trimmed
                if let query = try? PureXML.XPath.Query(path), query.nodes(over: root).contains(where: { $0 === node }) {
                    return true
                }
            }
            return false
        }

        fileprivate func applyTemplates(
            to nodes: [PureXML.Model.TreeNode],
            mode: String?,
            parameters: [Binding],
            _ context: XSLTContext,
        ) -> [ResultItem] {
            var items: [ResultItem] = []
            for (offset, node) in nodes.enumerated() {
                let nodeContext = XSLTContext(node: node, position: offset + 1, size: nodes.count, variables: context.variables, mode: mode)
                if let template = bestTemplate(for: node, mode: mode) {
                    items += instantiateTemplate(template, nodeContext, passing: parameters, from: context)
                } else {
                    items += builtInRule(node, mode: mode, nodeContext)
                }
            }
            return items
        }

        /// Binds the template's parameters (a passed `with-param` wins over the
        /// declared default) and instantiates its body.
        fileprivate func instantiateTemplate(
            _ template: Template,
            _ context: XSLTContext,
            passing parameters: [Binding],
            from caller: XSLTContext,
        ) -> [ResultItem] {
            var context = context
            context.importPrecedence = template.importPrecedence
            for parameter in template.parameters {
                if let passed = parameters.first(where: { $0.name == parameter.name }) {
                    context.variables[parameter.name] = variableValue(passed.select, passed.body, caller)
                } else {
                    context.variables[parameter.name] = variableValue(parameter.select, parameter.body, context)
                }
            }
            return instantiate(template.body, context)
        }

        private func builtInRule(_ node: PureXML.Model.TreeNode, mode: String?, _ context: XSLTContext) -> [ResultItem] {
            switch node.kind {
            case .element, .document:
                applyTemplates(to: node.children, mode: mode, parameters: [], context)
            case .text, .cdata:
                [.node(.text(node.value))]
            default:
                []
            }
        }

        // MARK: Instantiation

        fileprivate func instantiate(_ body: [Instruction], _ context: XSLTContext) -> [ResultItem] {
            var items: [ResultItem] = []
            var context = context
            for instruction in body {
                if termination.message != nil { break }
                switch instruction {
                case let .variable(name, select, varBody):
                    context.variables[name] = variableValue(select, varBody, context)
                case let .fallback(fallbackBody):
                    items += instantiate(fallbackBody, context)
                default:
                    items += evaluate(instruction, context)
                }
            }
            return items
        }

        private func variableValue(_ select: String?, _ body: [Instruction], _ context: XSLTContext) -> PureXML.XPath.Value {
            if let select { return value(select, context) ?? .string("") }
            return .string(Self.text(of: instantiate(body, context)))
        }

        fileprivate func value(_ expression: String, _ context: XSLTContext) -> PureXML.XPath.Value? {
            guard let query = try? PureXML.XPath.Query(expression) else { return nil }
            return try? query.value(
                at: context.node,
                position: context.position,
                size: context.size,
                variables: context.variables,
                functions: PureXML.XSLT.Library.table(current: context.node, keys: keyIndex, loader: documentLoader, decimalFormats: stylesheet.decimalFormats),
            )
        }

        fileprivate func selectNodes(_ expression: String, _ context: XSLTContext) -> [PureXML.Model.TreeNode] {
            value(expression, context)?.nodes?.compactMap(\.treeNode) ?? []
        }

        fileprivate func string(_ expression: String, _ context: XSLTContext) -> String {
            value(expression, context)?.string ?? ""
        }

        fileprivate func boolean(_ expression: String, _ context: XSLTContext) -> Bool {
            value(expression, context)?.boolean ?? false
        }

        fileprivate static func nodeOf(_ item: ResultItem) -> PureXML.Model.Node? {
            if case let .node(node) = item { return node }
            return nil
        }

        fileprivate static func text(of items: [ResultItem]) -> String {
            items.reduce(into: "") { result, item in
                if case let .node(node) = item { result += Self.stringValue(node) }
            }
        }

        private static func stringValue(_ node: PureXML.Model.Node) -> String {
            switch node {
            case let .text(value), let .cdata(value): value
            case let .element(element): element.children.reduce(into: "") { $0 += stringValue($1) }
            case let .document(children): children.reduce(into: "") { $0 += stringValue($1) }
            default: ""
            }
        }
    }
}

extension PureXML.XSLT.Transformer {
    // MARK: Instruction evaluation

    fileprivate func evaluate(_ instruction: PureXML.XSLT.Instruction, _ context: XSLTContext) -> [ResultItem] {
        simpleEvaluate(instruction, context) ?? structuralEvaluate(instruction, context)
    }

    private func simpleEvaluate(_ instruction: PureXML.XSLT.Instruction, _ context: XSLTContext) -> [ResultItem]? {
        switch instruction {
        case let .literalText(text): [.node(.text(text))]
        case let .valueOf(select): [.node(.text(string(select, context)))]
        case let .applyTemplates(select, mode, sorts, parameters):
            applyTemplates(
                to: sorted(selectNodes(select ?? "node()", context), sorts),
                mode: mode,
                parameters: parameters,
                context,
            )
        case let .forEach(select, sorts, body): forEach(select, sorts, body, context)
        case let .ifInstruction(test, body): boolean(test, context) ? instantiate(body, context) : []
        case let .choose(whens, otherwise): chooseInstruction(whens, otherwise, context)
        case let .copyOf(select): copyOf(select, context)
        case let .callTemplate(name, parameters): callTemplate(name, parameters, context)
        case .variable: []
        default: nil
        }
    }

    /// Instantiates an `xsl:message` body as its text; `terminate` records the
    /// signal so the transform aborts with it. Produces no result-tree output.
    private func message(_ terminate: Bool, _ body: [PureXML.XSLT.Instruction], _ context: XSLTContext) -> [ResultItem] {
        if terminate, termination.message == nil {
            termination.message = Self.text(of: instantiate(body, context))
        }
        return []
    }

    /// Builds a literal result element, rewriting its name and attribute names
    /// through any `xsl:namespace-alias` in effect.
    private func literalResult(
        _ name: PureXML.Model.QualifiedName,
        _ attributes: [PureXML.XSLT.LiteralAttribute],
        _ useAttributeSets: [String],
        _ body: [PureXML.XSLT.Instruction],
        _ context: XSLTContext,
    ) -> ResultItem {
        let aliasedAttributes = attributes.map { PureXML.XSLT.LiteralAttribute(name: aliased($0.name), value: $0.value) }
        return buildElement(name: aliased(name), literalAttributes: aliasedAttributes, useAttributeSets: useAttributeSets, body: body, context)
    }

    private func structuralEvaluate(_ instruction: PureXML.XSLT.Instruction, _ context: XSLTContext) -> [ResultItem] {
        switch instruction {
        case let .literalElement(name, attributes, useAttributeSets, body):
            [literalResult(name, attributes, useAttributeSets, body, context)]
        case let .element(nameTemplate, useAttributeSets, body):
            [buildElement(name: .init(avt(nameTemplate, context)), literalAttributes: [], useAttributeSets: useAttributeSets, body: body, context)]
        case let .attribute(nameTemplate, body):
            [.attribute(.init(avt(nameTemplate, context), Self.text(of: instantiate(body, context))))]
        case let .copy(body):
            copyInstruction(body, context)
        case let .number(count, _, format):
            [.node(.text(PureXML.XSLT.Numbering.value(of: context.node, count: count, format: format)))]
        case let .comment(body):
            [.node(.comment(Self.text(of: instantiate(body, context))))]
        case let .processingInstruction(name, body):
            [.node(.processingInstruction(target: avt(name, context), data: Self.text(of: instantiate(body, context))))]
        case let .message(terminate, body):
            message(terminate, body, context)
        case .applyImports:
            applyImports(context)
        default:
            []
        }
    }

    /// Re-applies templates to the current node in the current mode, considering
    /// only those below the current template's import precedence, falling back to
    /// the built-in rule when none match.
    private func applyImports(_ context: XSLTContext) -> [ResultItem] {
        if let template = bestTemplate(for: context.node, mode: context.mode, below: context.importPrecedence) {
            return instantiateTemplate(template, context, passing: [], from: context)
        }
        return builtInRule(context.node, mode: context.mode, context)
    }

    private func forEach(
        _ select: String,
        _ sorts: [PureXML.XSLT.Sort],
        _ body: [PureXML.XSLT.Instruction],
        _ context: XSLTContext,
    ) -> [ResultItem] {
        let nodes = sorted(selectNodes(select, context), sorts)
        var items: [ResultItem] = []
        for (offset, node) in nodes.enumerated() {
            items += instantiate(body, XSLTContext(node: node, position: offset + 1, size: nodes.count, variables: context.variables))
        }
        return items
    }

    private func chooseInstruction(
        _ whens: [PureXML.XSLT.Branch],
        _ otherwise: [PureXML.XSLT.Instruction],
        _ context: XSLTContext,
    ) -> [ResultItem] {
        for branch in whens where boolean(branch.test, context) {
            return instantiate(branch.body, context)
        }
        return instantiate(otherwise, context)
    }

    private func callTemplate(_ name: String, _ parameters: [PureXML.XSLT.Binding], _ context: XSLTContext) -> [ResultItem] {
        guard let template = stylesheet.templates.first(where: { $0.name == name }) else { return [] }
        return instantiateTemplate(template, context, passing: parameters, from: context)
    }

    private func copyOf(_ select: String, _ context: XSLTContext) -> [ResultItem] {
        guard let nodes = value(select, context)?.nodes else {
            // A non-node-set result copies as its string value.
            return value(select, context).map { [.node(.text($0.string))] } ?? []
        }
        return nodes.map { xnode in
            switch xnode {
            case let .tree(tree): .node(tree.node)
            case let .attribute(_, attribute): .attribute(attribute)
            case let .namespace(_, prefix, uri):
                .attribute(.init(prefix.isEmpty ? "xmlns" : "xmlns:\(prefix)", uri))
            }
        }
    }

    private func copyInstruction(_ body: [PureXML.XSLT.Instruction], _ context: XSLTContext) -> [ResultItem] {
        switch context.node.kind {
        case .element:
            [buildElement(name: context.node.name ?? .init(""), literalAttributes: [], useAttributeSets: [], body: body, context)]
        case .text, .cdata:
            [.node(.text(context.node.value))]
        default:
            instantiate(body, context)
        }
    }

    // MARK: Building elements

    private func buildElement(
        name: PureXML.Model.QualifiedName,
        literalAttributes: [PureXML.XSLT.LiteralAttribute],
        useAttributeSets: [String],
        body: [PureXML.XSLT.Instruction],
        _ context: XSLTContext,
    ) -> ResultItem {
        // Attribute sets are lowest precedence, then the element's literal
        // attributes, then its xsl:attribute body; a later same-named attribute
        // replaces an earlier one.
        var attributes = attributeSetAttributes(useAttributeSets, context, visiting: [])
        attributes += literalAttributes.map { PureXML.Model.Attribute(name: $0.name, value: avt($0.value, context)) }
        var children: [PureXML.Model.Node] = []
        for item in instantiate(body, context) {
            switch item {
            case let .attribute(attribute): attributes.append(attribute)
            case let .node(node): children.append(node)
            }
        }
        return .node(.element(.init(name: name, attributes: Self.deduplicated(attributes), children: children)))
    }

    /// The attributes contributed by `names` and the attribute sets they include,
    /// lower precedence first, with a `visiting` guard against recursive includes.
    private func attributeSetAttributes(_ names: [String], _ context: XSLTContext, visiting: Set<String>) -> [PureXML.Model.Attribute] {
        var result: [PureXML.Model.Attribute] = []
        for name in names where !visiting.contains(name) {
            guard let set = stylesheet.attributeSets[name] else { continue }
            result += attributeSetAttributes(set.use, context, visiting: visiting.union([name]))
            for item in instantiate(set.attributes, context) {
                if case let .attribute(attribute) = item { result.append(attribute) }
            }
        }
        return result
    }

    private func avt(_ template: PureXML.XSLT.ValueTemplate, _ context: XSLTContext) -> String {
        template.reduce(into: "") { result, part in
            switch part {
            case let .literal(text): result += text
            case let .expression(expression): result += string(expression, context)
            }
        }
    }

    private func sorted(_ nodes: [PureXML.Model.TreeNode], _ sorts: [PureXML.XSLT.Sort]) -> [PureXML.Model.TreeNode] {
        guard !sorts.isEmpty else { return nodes }
        return nodes.enumerated().sorted { lhs, rhs in
            for sort in sorts {
                let order = compareKeys(lhs.element, rhs.element, sort)
                if order != 0 { return order < 0 }
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private func compareKeys(_ lhs: PureXML.Model.TreeNode, _ rhs: PureXML.Model.TreeNode, _ sort: PureXML.XSLT.Sort) -> Int {
        let left = keyValue(sort.select, lhs)
        let right = keyValue(sort.select, rhs)
        var order: Int
        if sort.numeric {
            let leftNumber = PureXML.XPath.Value.parseNumber(left)
            let rightNumber = PureXML.XPath.Value.parseNumber(right)
            order = leftNumber == rightNumber ? 0 : (leftNumber < rightNumber ? -1 : 1)
        } else {
            order = left == right ? 0 : (left < right ? -1 : 1)
        }
        return sort.descending ? -order : order
    }

    private func keyValue(_ expression: String, _ node: PureXML.Model.TreeNode) -> String {
        guard let query = try? PureXML.XPath.Query(expression) else { return "" }
        return (try? query.value(at: node).string) ?? ""
    }
}
