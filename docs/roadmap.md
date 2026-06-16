# Roadmap

Living index of open work. **Pin [#167](https://github.com/mihaelamj/PureXML/issues/167)** on GitHub for the checklist view. Released **v0.2.0** (2026-06-16); pre-1.0 until the production-readiness gates in `docs/production-readiness.md` are earned.

## Current focus (priority order)

1. **#161**: cross-document schema composition (`include`/`import`/`redefine`): chameleon include + cross-container reference checks landed; attg/schZ XSTS burn-down still open.
2. **#158 / #159**: Particle Valid Restriction/Extension completion.
3. **#169**: located schema diagnostics (line/column).
4. **#172–#174**: instance-validation cluster tasks.

Parallel: **#130** (XSLT suite), **#139** (performance epic; tasks [#175](https://github.com/mihaelamj/PureXML/issues/175)–[#178](https://github.com/mihaelamj/PureXML/issues/178)).

**M1 done:** #171 schema differential harness (closed; opt-in; 231 XSTS oracle disagreements pinned) + generative fuzz + validation framework (#92).

## XSTS gates (v0.2.0 baselines)

| Gate | Now | Issue |
|---|---|---|
| Valid schemas rejected | 1 | [#148](https://github.com/mihaelamj/PureXML/issues/148) |
| Invalid schemas accepted | 261 | [#145](https://github.com/mihaelamj/PureXML/issues/145) |
| Valid instances rejected | 99 | [#146](https://github.com/mihaelamj/PureXML/issues/146) |
| Invalid instances accepted | 147 | [#147](https://github.com/mihaelamj/PureXML/issues/147) |

Gates are **metric trackers**, not implementation tasks. Pick up **task** issues; ratchet baselines in `Tests/XSTSSuiteTests.swift` when counts fall.

## Milestones

| Milestone | Exit criteria | Key issues |
|---|---|---|
| M1: Trust the oracle | Reference differential + fuzz | ~~#171~~ (closed), fuzz |
| M2: Schema compiles correctly | #145 to 0 | #161, #158, #159 |
| M3: Instances validate correctly | #146, #147 to 0 | #172, #173, #174 |
| M4: IDE-ready diagnostics | Located errors, proven bounds | #169 |
| M5: 1.0 | All gates at 0 | #148 (closed at floor), #130, #139 |

## Labels

| Label | Meaning |
|---|---|
| `epic` | Grouping issue |
| `gate` | XSTS outcome metric |
| `task` | Implementation work |
| `area-schema` / `area-instance` / `area-infra` / `area-xslt` / `area-perf` | Subsystem |
| `priority-P0` / `P1` / `P2` | Critical path vs parallel |

## Related docs

- `docs/production-readiness.md`: the bar for IDE authority
- `docs/schema-validity-burndown.md`: schema-side burn-down protocol
- `docs/xsts-deviations.md`: deviation taxonomy and documented floors
