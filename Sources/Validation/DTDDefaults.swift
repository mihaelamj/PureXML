public extension PureXML.Validation.DTDSchema {
    /// Returns `node` with DTD attribute defaults applied: every element gains any
    /// attribute its `<!ATTLIST>` declares with a default or `#FIXED` value and
    /// that the element omits. `#REQUIRED` and `#IMPLIED` add nothing. The injected
    /// values are the normalized defaults from the declaration, so an editor reads
    /// the same effective attributes a validating processor would see.
    func applyingDefaults(to node: PureXML.Model.Node) -> PureXML.Model.Node {
        // Rebuilt bottom-up (iterative) so a deeply-nested document does not
        // overflow the stack; each element gains its DTD-declared defaults once its
        // children are rebuilt.
        node.rebuildingBottomUp { original, rebuiltChildren in
            switch original {
            case let .element(element):
                var result = element
                result.children = rebuiltChildren
                return .element(withDefaults(result))
            case .document:
                return .document(rebuiltChildren)
            default:
                return original
            }
        }
    }

    /// Adds the attributes `element`'s `<!ATTLIST>` declares with a default or
    /// `#FIXED` value and that the element omits. `result.children` is assumed
    /// already set by the caller.
    private func withDefaults(_ element: PureXML.Model.Element) -> PureXML.Model.Element {
        var result = element
        guard let declarations = attributes[element.name.description] else { return result }
        for declaration in declarations {
            guard let value = Self.defaultValue(declaration) else { continue }
            let present = result.attributes.contains {
                $0.name.description == declaration.name || $0.name.localName == declaration.name
            }
            if !present { result.attributes.append(PureXML.Model.Attribute(declaration.name, value)) }
        }
        return result
    }

    private static func defaultValue(_ declaration: PureXML.Validation.AttributeDeclaration) -> String? {
        switch declaration.defaultDecl {
        case let .value(value), let .fixed(value): value
        case .required, .implied: nil
        }
    }
}
