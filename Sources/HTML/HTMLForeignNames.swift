extension PureXML.HTML {
    /// The HTML5 "adjust SVG element names" table: the SVG elements whose correct
    /// names are camel-cased, keyed by the lowercased form the tokenizer produces.
    /// Applied when materializing an element in the SVG namespace so a parsed
    /// `<foreignObject>` or `<lineargradient>` carries its canonical SVG name.
    enum ForeignNames {
        static let svgElements: [String: String] = [
            "altglyph": "altGlyph", "altglyphdef": "altGlyphDef", "altglyphitem": "altGlyphItem",
            "animatecolor": "animateColor", "animatemotion": "animateMotion", "animatetransform": "animateTransform",
            "clippath": "clipPath", "feblend": "feBlend", "fecolormatrix": "feColorMatrix",
            "fecomponenttransfer": "feComponentTransfer", "fecomposite": "feComposite", "feconvolvematrix": "feConvolveMatrix",
            "fediffuselighting": "feDiffuseLighting", "fedisplacementmap": "feDisplacementMap", "fedistantlight": "feDistantLight",
            "fedropshadow": "feDropShadow", "feflood": "feFlood", "fefunca": "feFuncA",
            "fefuncb": "feFuncB", "fefuncg": "feFuncG", "fefuncr": "feFuncR",
            "fegaussianblur": "feGaussianBlur", "feimage": "feImage", "femerge": "feMerge",
            "femergenode": "feMergeNode", "femorphology": "feMorphology", "feoffset": "feOffset",
            "fepointlight": "fePointLight", "fespecularlighting": "feSpecularLighting", "fespotlight": "feSpotLight",
            "fetile": "feTile", "feturbulence": "feTurbulence", "foreignobject": "foreignObject",
            "glyphref": "glyphRef", "lineargradient": "linearGradient", "radialgradient": "radialGradient",
            "textpath": "textPath",
        ]
    }
}
