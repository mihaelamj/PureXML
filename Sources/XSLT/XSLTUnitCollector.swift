/// The state accumulated while flattening one unit: its queued
/// declarations, the import-precedence counter, and the included
/// documents' roots. Tree nodes hold their parents weakly, so the
/// roots must stay retained until the declarations are parsed or the
/// ancestor chain (xmlns declarations, exclusions, aliases in scope)
/// silently disappears.
struct XSLTUnitCollector {
    var counter: Int
    var declarations: [(XSLTTree, String)] = []
    var retainedRoots: [XSLTTree] = []
    /// The resolved hrefs on the active load chain (ancestors only, not
    /// siblings): re-entry means an include or import cycle, which is
    /// dropped; a diamond (two units loading the same sheet) stays legal.
    var chain: Set<String> = []
}
