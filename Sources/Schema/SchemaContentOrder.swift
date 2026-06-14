extension PureXML.Schema.XSDParser {
    /// Content-model order and cardinality for a `complexContent` derivation, the
    /// ordering complement to the set-membership `allowedChildren` check (which
    /// admits the right child names but not their sequence or count).
    ///
    /// A `restriction`/`extension` inside `complexContent` has the model
    /// `(annotation?, (group | all | choice | sequence)?, (attribute | attributeGroup)*, anyAttribute?)`
    /// (XSD 1.0 Structures): an optional model group, then any number of
    /// `attribute`/`attributeGroup`, then an optional `anyAttribute`. A second model
    /// group, a model group after an attribute, an attribute after `anyAttribute`, or
    /// a second `anyAttribute` (the ctG/ctH families) was previously accepted.
    /// Only the `complexContent` context is checked, where a model group is part of
    /// the model; a `simpleContent` derivation (facets, no model group) has a
    /// different model and is left to its own rules.
    static func complexContentOrderErrors(_ complexContent: XSDTree) -> [String] {
        var errors: [String] = []
        for derivation in PureXML.Schema.XSDNode.elementChildren(complexContent) {
            guard let local = PureXML.Schema.XSDNode.localName(derivation),
                  local == "restriction" || local == "extension"
            else { continue }
            let names = PureXML.Schema.XSDNode.elementChildren(derivation)
                .filter { $0.name?.namespaceURI == xsdNamespace }
                .compactMap(PureXML.Schema.XSDNode.localName)
                .filter { $0 != "annotation" }
            if let reason = slotOrderViolation(names, slots: complexDerivationSlots) {
                errors.append("the content of a complexContent '\(local)' must be a model group, then attributes, then anyAttribute: \(reason)")
            }
        }
        return errors
    }

    /// Content-model order for a complexType's shorthand form (no `simpleContent`/
    /// `complexContent`), which shares the derivation's slot model: an optional model
    /// group, then `attribute`/`attributeGroup`, then an optional `anyAttribute`.
    /// `complexTypeContentErrors` already checks cardinality and the exclusivity of a
    /// content spec with model groups/attributes; this adds the ordering (a model
    /// group after an attribute, an attribute after `anyAttribute`, a second
    /// `anyAttribute`). `annotation` and the content specs are not part of the slots.
    static func complexTypeOrderErrors(_ complexType: XSDTree) -> [String] {
        let names = PureXML.Schema.XSDNode.elementChildren(complexType)
            .filter { $0.name?.namespaceURI == xsdNamespace }
            .compactMap(PureXML.Schema.XSDNode.localName)
            .filter { $0 != "annotation" && $0 != "simpleContent" && $0 != "complexContent" }
        guard let reason = slotOrderViolation(names, slots: complexDerivationSlots) else { return [] }
        return ["the content of a complexType must be a model group, then attributes, then anyAttribute: \(reason)"]
    }

    /// The ordered slots of a `complexContent` derivation: each lists its admitted
    /// names and how many children may fill it (nil is unbounded).
    private static let complexDerivationSlots: [(members: Set<String>, max: Int?)] = [
        (["group", "all", "choice", "sequence"], 1),
        (["attribute", "attributeGroup"], nil),
        (["anyAttribute"], 1),
    ]

    /// The first child that does not fit the ordered slot model, or nil. Each child
    /// must fill the current slot or one after it (order is forward-only), and a slot
    /// with a finite `max` may not be overfilled.
    private static func slotOrderViolation(_ children: [String], slots: [(members: Set<String>, max: Int?)]) -> String? {
        var slotIndex = 0
        var counts = [Int](repeating: 0, count: slots.count)
        for child in children {
            var index = slotIndex
            while index < slots.count, !slots[index].members.contains(child) {
                index += 1
            }
            guard index < slots.count else { return "'\(child)' is out of order" }
            counts[index] += 1
            if let maximum = slots[index].max, counts[index] > maximum {
                return "'\(child)' appears too many times"
            }
            slotIndex = index
        }
        return nil
    }
}
