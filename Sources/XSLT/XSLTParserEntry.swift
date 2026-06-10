/// The accumulating halves of a stylesheet under compilation.
struct Parts {
    var templates: [PureXML.XSLT.Template] = []
    var globals: [PureXML.XSLT.Instruction] = []
    var keys: [PureXML.XSLT.Key] = []
    var output = PureXML.XSLT.Output()
    var stripSpace: Set<String> = []
    var preserveSpace: Set<String> = []
    var attributeSets: [String: PureXML.XSLT.AttributeSet] = [:]
    var decimalFormats: [String: PureXML.XSLT.DecimalFormat] = [:]
    var namespaceAliases: [String: PureXML.XSLT.NamespaceAlias] = [:]

    var stylesheet: PureXML.XSLT.Stylesheet {
        PureXML.XSLT.Stylesheet(
            templates: templates,
            globals: globals,
            keys: keys,
            output: output,
            stripSpace: stripSpace,
            preserveSpace: preserveSpace,
            attributeSets: attributeSets,
            decimalFormats: decimalFormats,
            namespaceAliases: namespaceAliases,
        )
    }

    /// Folds a sub-stylesheet in: an import has lower precedence, so its globals
    /// come before and its output is overridden by this stylesheet's.
    mutating func fold(_ sub: PureXML.XSLT.Stylesheet?, isImport: Bool) {
        guard let sub else { return }
        templates += sub.templates
        keys += sub.keys
        stripSpace.formUnion(sub.stripSpace)
        preserveSpace.formUnion(sub.preserveSpace)
        attributeSets.merge(sub.attributeSets) { mine, _ in mine }
        decimalFormats.merge(sub.decimalFormats) { mine, _ in mine }
        namespaceAliases.merge(sub.namespaceAliases) { mine, _ in mine }
        globals = isImport ? sub.globals + globals : globals + sub.globals
        output = isImport ? sub.output.merged(with: output) : output.merged(with: sub.output)
    }
}

extension PureXML.XSLT.XSLTParser {
    static func parse(_ xsl: String, loader: (String) -> String? = { _ in nil }) throws -> PureXML.XSLT.Stylesheet {
        let root = try PureXML.parseTree(xsl, limits: .init(allowDoctype: true))
        if let top = stylesheetElement(root) {
            return compile(top, loader: loader, precedence: 0)
        }
        // Simplified syntax (2.3): a literal result element carrying
        // xsl:version becomes the body of a match="/" template.
        let literal = XSLTNode.elementChildren(root).first
        let isSimplified = literal?.attributes.contains { $0.name.prefix == "xsl" && $0.name.localName == "version" } ?? false
        if isSimplified, let literal, let body = instruction(literal) {
            var parts = Parts()
            parts.templates.append(PureXML.XSLT.Template(
                match: "/",
                name: nil,
                mode: nil,
                priority: 0,
                importPrecedence: 0,
                parameters: [],
                body: [body],
            ))
            return parts.stylesheet
        }
        throw PureXML.XSLT.XSLTError.notAStylesheet
    }

    static func stylesheetElement(_ root: XSLTTree) -> XSLTTree? {
        guard let top = XSLTNode.elementChildren(root).first, XSLTNode.isXSL(top),
              XSLTNode.localName(top) == "stylesheet" || XSLTNode.localName(top) == "transform"
        else {
            return nil
        }
        return top
    }
}
