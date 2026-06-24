/// The accumulating halves of a stylesheet under compilation.
struct Parts {
    var templates: [PureXML.XSLT.Template] = []
    var globals: [PureXML.XSLT.GlobalDeclaration] = []
    var keys: [PureXML.XSLT.Key] = []
    var output = PureXML.XSLT.Output()
    var stripSpace: Set<String> = []
    var parameterNames: Set<String> = []
    var preserveSpace: Set<String> = []
    var attributeSets: [String: [PureXML.XSLT.AttributeSet]] = [:]
    var decimalFormats: [String: PureXML.XSLT.DecimalFormat] = [:]
    var namespaceAliases: [String: PureXML.XSLT.NamespaceAlias] = [:]

    var stylesheet: PureXML.XSLT.Stylesheet {
        // Same-name globals resolve by import precedence. Imports fold in
        // precedence order (earlier imports lower, the unit's own
        // declarations appended last), so the last same-name entry wins.
        var seen = Set<String>()
        let resolvedGlobals: [PureXML.XSLT.GlobalDeclaration] = globals.reversed().filter { declaration in
            guard let name = Self.globalName(declaration.instruction) else { return true }
            return seen.insert(name).inserted
        }.reversed()
        var sheet = PureXML.XSLT.Stylesheet(
            templates: templates,
            globals: resolvedGlobals,
            keys: keys,
            output: output,
            stripSpace: stripSpace,
            preserveSpace: preserveSpace,
            attributeSets: attributeSets,
            decimalFormats: decimalFormats,
            namespaceAliases: namespaceAliases,
        )
        sheet.parameterNames = parameterNames
        return sheet
    }

    private static func globalName(_ instruction: PureXML.XSLT.Instruction) -> String? {
        guard case let .variable(name, _, _) = instruction else { return nil }
        return name
    }

    /// Folds a sub-stylesheet in. Folds happen in import-precedence order
    /// (earlier imports first, the unit's own declarations absorbed last),
    /// so later contributions uniformly take precedence: globals append (the
    /// stylesheet getter keeps the last same-name entry), attribute-set
    /// definitions concatenate (later ones expand later and win), and the
    /// later output settings layer on top.
    mutating func fold(_ sub: PureXML.XSLT.Stylesheet?, isImport _: Bool) {
        guard let sub else { return }
        templates += sub.templates
        keys += sub.keys
        stripSpace.formUnion(sub.stripSpace)
        parameterNames.formUnion(sub.parameterNames)
        preserveSpace.formUnion(sub.preserveSpace)
        attributeSets.merge(sub.attributeSets) { mine, theirs in mine + theirs }
        decimalFormats.merge(sub.decimalFormats) { _, theirs in theirs }
        namespaceAliases.merge(sub.namespaceAliases) { _, theirs in theirs }
        globals += sub.globals
        output = output.merged(with: sub.output)
    }
}

extension PureXML.XSLT.XSLTParser {
    static func parse(_ xsl: String, loader: @escaping (String) -> String? = { _ in nil }) throws -> PureXML.XSLT.Stylesheet {
        let root = try PureXML.parseTree(xsl, limits: .init(allowDoctype: true), resolver: PureXML.XSLT.loaderResolver(loader))
        let usesRawText = containsSubstring(xsl, "disable-output-escaping")
        if let top = stylesheetElement(root) {
            var counter = 0
            var sheet = compile(top, loader: loader, counter: &counter)
            sheet.usesRawText = usesRawText
            return sheet
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
            var sheet = parts.stylesheet
            sheet.usesRawText = usesRawText
            return sheet
        }
        throw PureXML.XSLT.XSLTError.notAStylesheet
    }

    /// Substring search without Foundation (the stdlib String-argument
    /// `contains` needs a newer platform floor).
    private static func containsSubstring(_ text: String, _ needle: String) -> Bool {
        guard let head = needle.first else { return true }
        var search = text[...]
        while let start = search.firstIndex(of: head) {
            if search[start...].hasPrefix(needle) { return true }
            search = search[search.index(after: start)...]
        }
        return false
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
