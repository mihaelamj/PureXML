extension HTMLDocument {
    /// The elements the table insertion modes place directly (so they are never
    /// foster-parented out of a table).
    private static let tableScope: Set<String> = [
        "table", "caption", "colgroup", "col", "tbody", "thead", "tfoot", "tr", "td", "th",
    ]

    /// The table-structural elements that, when current, mean a stray non-table
    /// node must be foster-parented rather than nested.
    private static let tableContexts: Set<String> = ["table", "tbody", "thead", "tfoot", "tr"]

    /// Inserts an opened element, foster-parenting it before the table when it is a
    /// non-table element appearing in table context (the HTML5 rule for stray
    /// flow content inside a table).
    func placeElement(_ element: PureXML.Model.TreeNode, name: String) {
        if !Self.tableScope.contains(name), inTableContext() {
            fosterParent(element)
        } else {
            openBody.last?.append(element)
        }
    }

    /// Inserts a text node, foster-parenting it out of a table when in table
    /// context (character data is not allowed directly inside table structure).
    func placeText(_ node: PureXML.Model.TreeNode) {
        if inTableContext() {
            fosterParent(node)
        } else {
            openBody.last?.append(node)
        }
    }

    private func inTableContext() -> Bool {
        guard let current = openBody.last else { return false }
        return Self.tableContexts.contains(tagName(current))
    }

    /// Inserts `node` immediately before the nearest open table in that table's
    /// parent; if the table has no parent yet, falls back to ordinary insertion.
    private func fosterParent(_ node: PureXML.Model.TreeNode) {
        guard let table = openBody.last(where: { tagName($0) == "table" }), let parent = table.parent else {
            openBody.last?.append(node)
            return
        }
        parent.insert(node, before: table)
    }
}
