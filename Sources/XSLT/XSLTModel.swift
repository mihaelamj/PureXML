public extension PureXML.XSLT {
    /// One part of an attribute value template: literal text, or an embedded XPath
    /// expression written `{expr}`.
    enum ValuePart: Sendable {
        case literal(String)
        case expression(String)
    }

    /// An attribute value template (a string with `{expr}` substitutions).
    typealias ValueTemplate = [ValuePart]

    /// A literal-result-element attribute, whose value is an attribute value
    /// template.
    struct LiteralAttribute: Sendable {
        public var name: PureXML.Model.QualifiedName
        public var value: ValueTemplate
    }

    /// Which case sorts first among strings equal apart from case.
    enum CaseOrder: Sendable {
        case upperFirst
        case lowerFirst
    }

    /// A sort specification for `apply-templates`/`for-each`.
    struct Sort: Sendable {
        public var select: String
        public var descending: Bool
        public var numeric: Bool
        /// `case-order`: when set, the comparison is case-insensitive and this
        /// breaks ties; when nil, the comparison is the default codepoint order.
        public var caseOrder: CaseOrder?

        public init(select: String, descending: Bool, numeric: Bool, caseOrder: CaseOrder? = nil) {
            self.select = select
            self.descending = descending
            self.numeric = numeric
            self.caseOrder = caseOrder
        }
    }

    /// One instruction of a template body (a sequence constructor item).
    indirect enum Instruction: Sendable {
        /// Literal character data copied to the result.
        case literalText(String)
        /// `xsl:value-of`: the string value of an XPath expression.
        case valueOf(select: String, raw: Bool)
        /// `xsl:apply-templates` with an optional node-set selection, mode, sorts,
        /// and passed parameters.
        case applyTemplates(select: String?, mode: String?, sorts: [Sort], parameters: [Binding])
        /// `xsl:for-each` over a node-set.
        case forEach(select: String, sorts: [Sort], body: [Instruction])
        /// `xsl:if`.
        case ifInstruction(test: String, body: [Instruction])
        /// `xsl:choose` with its `when` branches and optional `otherwise`.
        case choose(whens: [Branch], otherwise: [Instruction])
        /// A literal result element, copied to the output with its attributes and
        /// any `use-attribute-sets`.
        case literalElement(name: PureXML.Model.QualifiedName, attributes: [LiteralAttribute], namespaces: [String: String], useAttributeSets: [String], body: [Instruction])
        /// `xsl:element` whose name is an attribute value template, with any
        /// `use-attribute-sets`.
        case element(name: ValueTemplate, namespace: ValueTemplate?, namespaces: [String: String], useAttributeSets: [String], body: [Instruction])
        /// `xsl:attribute` whose name is an attribute value template.
        case attribute(name: ValueTemplate, namespace: ValueTemplate?, namespaces: [String: String], body: [Instruction])
        /// `xsl:copy`: a shallow copy of the context node.
        case copy(useAttributeSets: [String], body: [Instruction])
        /// `xsl:copy-of`: a deep copy of a selected node-set.
        case copyOf(select: String)
        /// `xsl:call-template` by name with passed parameters.
        case callTemplate(name: String, parameters: [Binding])
        /// `xsl:variable` bound for the rest of the sequence constructor.
        case variable(name: String, select: String?, body: [Instruction])
        /// `xsl:number`: a generated sequence number for the context node.
        case number(NumberSpec)
        /// `xsl:comment`: a comment node whose text is the instantiated body.
        case comment(body: [Instruction])
        /// `xsl:processing-instruction` whose target is `name` and whose data is
        /// the instantiated body.
        case processingInstruction(name: ValueTemplate, body: [Instruction])
        /// `xsl:message`: instantiates its body as a diagnostic. `terminate` ends
        /// the transformation with that text; it produces no result-tree output.
        case message(terminate: Bool, body: [Instruction])
        /// `xsl:apply-imports`: re-applies templates to the current node, in the
        /// current mode, considering only templates of lower import precedence.
        case applyImports
        /// The `xsl:fallback` content of an unrecognized XSLT element, instantiated
        /// in its place under forwards-compatible processing.
        case fallback(body: [Instruction])
    }

    /// The `xsl:output` controls that shape serialization: the output method, and
    /// the declaration and indentation settings. Each is nil when unspecified, so
    /// the serializer falls back to the caller's options.
    struct Output: Sendable {
        public var method: String?
        public var indent: Bool?
        public var omitXMLDeclaration: Bool?
        public var encoding: String?
        public var version: String?
        public var standalone: Bool?
        /// The `doctype-public` / `doctype-system` identifiers: when either is set,
        /// a `<!DOCTYPE>` for the result's root element is emitted before it.
        public var doctypePublic: String?
        public var doctypeSystem: String?
        /// Element names whose text content is emitted in `<![CDATA[…]]>` sections.
        public var cdataSectionElements: Set<String>

        public init(
            method: String? = nil,
            indent: Bool? = nil,
            omitXMLDeclaration: Bool? = nil,
            encoding: String? = nil,
            version: String? = nil,
            standalone: Bool? = nil,
            doctypePublic: String? = nil,
            doctypeSystem: String? = nil,
            cdataSectionElements: Set<String> = [],
        ) {
            self.method = method
            self.indent = indent
            self.omitXMLDeclaration = omitXMLDeclaration
            self.encoding = encoding
            self.version = version
            self.standalone = standalone
            self.doctypePublic = doctypePublic
            self.doctypeSystem = doctypeSystem
            self.cdataSectionElements = cdataSectionElements
        }

        /// This output's settings with `other`'s non-nil settings layered over them.
        func merged(with other: Output) -> Output {
            Output(
                method: other.method ?? method,
                indent: other.indent ?? indent,
                omitXMLDeclaration: other.omitXMLDeclaration ?? omitXMLDeclaration,
                encoding: other.encoding ?? encoding,
                version: other.version ?? version,
                standalone: other.standalone ?? standalone,
                doctypePublic: other.doctypePublic ?? doctypePublic,
                doctypeSystem: other.doctypeSystem ?? doctypeSystem,
                cdataSectionElements: cdataSectionElements.union(other.cdataSectionElements),
            )
        }
    }

    /// An `xsl:namespace-alias` target: the result namespace (and its prefix) that
    /// a literal result element's stylesheet namespace is rewritten to on output.
    struct NamespaceAlias: Sendable {
        public var uri: String?
        public var prefix: String?

        public init(uri: String?, prefix: String?) {
            self.uri = uri
            self.prefix = prefix
        }
    }

    /// The attribute bundle of an `xsl:number` instruction: the numbering
    /// level, the count/from patterns, an explicit value expression, the
    /// format string, and the digit grouping settings.
    struct NumberSpec: Sendable {
        var level: String
        var count: String?
        var from: String?
        var value: String?
        var format: String
        var groupingSeparator: String?
        var groupingSize: Int?
    }

    /// The symbols an `xsl:decimal-format` sets for `format-number`: those used in
    /// the picture (digit places, separators, percent) and in the output. The
    /// defaults are the XSLT standard format.
    struct DecimalFormat: Sendable {
        public var decimalSeparator: Character = "."
        public var groupingSeparator: Character = ","
        public var percent: Character = "%"
        public var perMille: Character = "\u{2030}"
        public var zeroDigit: Character = "0"
        public var digit: Character = "#"
        public var patternSeparator: Character = ";"
        public var minusSign: Character = "-"
        public var infinity: String = "Infinity"
        public var notANumber: String = "NaN"

        public init() {}
    }

    /// An `xsl:attribute-set`: the `xsl:attribute` instructions it contributes and
    /// the other attribute sets it includes (`use-attribute-sets`).
    struct AttributeSet: Sendable {
        public var attributes: [Instruction]
        public var use: [String]

        public init(attributes: [Instruction], use: [String]) {
            self.attributes = attributes
            self.use = use
        }
    }

    /// An `xsl:key` declaration: a name, the nodes it indexes (a match pattern),
    /// and the key value of each (a `use` expression).
    struct Key: Sendable {
        public var name: String
        public var match: String
        public var use: String
    }

    /// One `xsl:when` branch of a choose.
    struct Branch: Sendable {
        public var test: String
        public var body: [Instruction]
    }

    /// A name binding: an `xsl:param` declaration (with a default) or an
    /// `xsl:with-param` value, supplied either by `select` or by a body.
    struct Binding: Sendable {
        public var name: String
        public var select: String?
        public var body: [Instruction]
    }

    /// A template rule: a match pattern and/or a name, a mode, a priority, its
    /// import precedence (higher wins, used to resolve `xsl:import`), its declared
    /// parameters, and a body.
    struct Template: Sendable {
        public var match: String?
        public var name: String?
        public var mode: String?
        public var priority: Double
        public var importPrecedence: Int
        public var parameters: [Binding]
        public var body: [Instruction]
    }

    /// A compiled stylesheet: its template rules, global variables, keys, output
    /// controls, and the `xsl:strip-space`/`xsl:preserve-space` name tests (with
    /// `xsl:include`/`xsl:import` already folded in).
    struct Stylesheet: Sendable {
        public var templates: [Template]
        public var globals: [Instruction]
        public var keys: [Key]
        public var output: Output
        /// Element name tests whose whitespace-only text children are stripped from
        /// the source (an NCName, a qualified name, or `*`).
        public var stripSpace: Set<String>
        /// Element name tests that keep their whitespace, overriding `stripSpace`.
        public var preserveSpace: Set<String>
        /// Named `xsl:attribute-set` declarations, keyed by name.
        public var attributeSets: [String: AttributeSet]
        /// `xsl:decimal-format` declarations for `format-number`, keyed by name; the
        /// empty key is the default (unnamed) format.
        public var decimalFormats: [String: DecimalFormat]
        /// `xsl:namespace-alias` rewrites, keyed by the stylesheet namespace URI
        /// (the empty key is the no-namespace/default case).
        public var namespaceAliases: [String: NamespaceAlias]

        public init(
            templates: [Template],
            globals: [Instruction],
            keys: [Key],
            output: Output,
            stripSpace: Set<String> = [],
            preserveSpace: Set<String> = [],
            attributeSets: [String: AttributeSet] = [:],
            decimalFormats: [String: DecimalFormat] = [:],
            namespaceAliases: [String: NamespaceAlias] = [:],
        ) {
            self.templates = templates
            self.globals = globals
            self.keys = keys
            self.output = output
            self.stripSpace = stripSpace
            self.preserveSpace = preserveSpace
            self.attributeSets = attributeSets
            self.decimalFormats = decimalFormats
            self.namespaceAliases = namespaceAliases
        }
    }
}
