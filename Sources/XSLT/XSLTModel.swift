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

    /// A sort specification for `apply-templates`/`for-each`.
    struct Sort: Sendable {
        public var select: String
        public var descending: Bool
        public var numeric: Bool
    }

    /// One instruction of a template body (a sequence constructor item).
    indirect enum Instruction: Sendable {
        /// Literal character data copied to the result.
        case literalText(String)
        /// `xsl:value-of`: the string value of an XPath expression.
        case valueOf(select: String)
        /// `xsl:apply-templates` with an optional node-set selection, mode, sorts,
        /// and passed parameters.
        case applyTemplates(select: String?, mode: String?, sorts: [Sort], parameters: [Binding])
        /// `xsl:for-each` over a node-set.
        case forEach(select: String, sorts: [Sort], body: [Instruction])
        /// `xsl:if`.
        case ifInstruction(test: String, body: [Instruction])
        /// `xsl:choose` with its `when` branches and optional `otherwise`.
        case choose(whens: [Branch], otherwise: [Instruction])
        /// A literal result element, copied to the output with its attributes.
        case literalElement(name: PureXML.Model.QualifiedName, attributes: [LiteralAttribute], body: [Instruction])
        /// `xsl:element` whose name is an attribute value template.
        case element(name: ValueTemplate, body: [Instruction])
        /// `xsl:attribute` whose name is an attribute value template.
        case attribute(name: ValueTemplate, body: [Instruction])
        /// `xsl:copy`: a shallow copy of the context node.
        case copy(body: [Instruction])
        /// `xsl:copy-of`: a deep copy of a selected node-set.
        case copyOf(select: String)
        /// `xsl:call-template` by name with passed parameters.
        case callTemplate(name: String, parameters: [Binding])
        /// `xsl:variable` bound for the rest of the sequence constructor.
        case variable(name: String, select: String?, body: [Instruction])
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
    /// declared parameters, and a body.
    struct Template: Sendable {
        public var match: String?
        public var name: String?
        public var mode: String?
        public var priority: Double
        public var parameters: [Binding]
        public var body: [Instruction]
    }

    /// A compiled stylesheet: its template rules and global variables.
    struct Stylesheet: Sendable {
        public var templates: [Template]
        public var globals: [Instruction]
    }
}
