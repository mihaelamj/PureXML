extension PureXML.XSLT.Transformer {
    /// A top-level variable or parameter declaration, extracted from the
    /// stylesheet's globals for fixpoint evaluation.
    private struct Global {
        let name: String
        let select: String?
        let body: [PureXML.XSLT.Instruction]
        let base: String
    }

    /// The global variable bindings, resolved to a fixpoint so references
    /// between top-level variables and parameters hold in any document order
    /// (XSLT 1.0 section 11.4). Evaluating once top-to-bottom would leave a
    /// forward reference (a global declared before the one it uses) unresolved.
    /// A DAG of N globals settles in at most N passes; a pass that changes
    /// nothing stops early; a genuine circular reference stops at the cap with
    /// the offending variables left at their last value.
    func evaluatedGlobals() -> [String: PureXML.XPath.Value] {
        var variables: [String: PureXML.XPath.Value] = [:]
        let globals: [Global] = stylesheet.globals.compactMap {
            guard case let .variable(name, select, body) = $0.instruction else { return nil }
            return Global(name: name, select: select, body: body, base: $0.baseURI)
        }
        // A caller-supplied value overrides an xsl:param default and is fixed.
        for global in globals where stylesheet.parameterNames.contains(global.name) {
            if let supplied = parameters[global.name] { variables[global.name] = .string(supplied) }
        }
        for _ in 0 ..< max(1, globals.count) {
            var changed = false
            for global in globals where !(stylesheet.parameterNames.contains(global.name) && parameters[global.name] != nil) {
                let context = XSLTContext(node: root, position: 1, size: 1, variables: variables, baseURI: global.base)
                let value = variableValue(global.select, global.body, context)
                if variables[global.name] != value {
                    variables[global.name] = value
                    changed = true
                }
            }
            if !changed { break }
        }
        return variables
    }
}
