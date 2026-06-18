# Git and Issue-Tracker Discipline

Conventions for issues, labels, pull requests, branches, commits, and remotes. Commit-*message* format (the `<type>(<scope>): summary` shape) is a separate convention; this file covers everything around it.

A repo that adopts these rules should ship the mechanical backstops that enforce them: issue forms, a PR template, a label set, and git hooks. The rules below are the durable conventions those mechanisms encode. Hooks live under `.git/` and are not cloned, so install them per clone, per machine.

## 1. Issue tracker

### Rule 1.1: Status block at the top, dated

Every issue body carries a `## Status (YYYY-MM-DD)` heading as the first section. New-issue form templates make this required.

When state changes (work starts, acceptance bullets ship, scope narrows, deps close), edit the status block in place with a new date line. The rest of the body stays as the original framing.

**Why**: bodies without a dated status block age into fiction within a month. Issues with a status block age well; the ones without age into wrong-default-value claims that shallow audits pass as "well-written, keep."

### Rule 1.2: No line numbers in issue bodies

File references use symbol names, not `Foo.swift:142`. Lines drift on every change; symbols do not. When you need a line anchor, write `Foo.swift (the searchSymbols function)` so the symbol survives even if the line moves.

**Why**: line anchors go dead within one change cycle the moment a file is split or reordered.

### Rule 1.3: No phantom paths

Every backtick-quoted file path in an issue body must EXIST in the repo (or in a declared sibling repo) at write time. A mechanical check is straightforward: extract backtick-quoted paths, check the filesystem, flag missing ones.

**Why**: a cited file that was never written is a fabrication that propagates. The work it implies may be real, but the path is a lie until the file exists. File it as future work instead of citing a path that is not there.

### Rule 1.4: Cross-reference hygiene

When citing `#NNN` in blocker phrasing ("blocked on", "pending in", "depends on", "after #N lands", "gated on", "awaits", "waiting on"), the referenced issue must be OPEN at write time. When it closes, edit the citing issue: remove the cross-reference, or rewrite the sentence to say the dep shipped.

**Why**: "blocked on #X" where #X closed weeks earlier is a silent dependency lie. Wrong issue numbers are worse: they point a reader at unrelated work.

### Rule 1.5: Schema and code claims are checkable

Do not cite `<table>.<column>` shapes, function signatures, or default values you have not verified against current source. When the claim is structural (a schema column, a config default, a flag name), an audit script can mechanically verify it. Migrations move columns; flag defaults change; bodies do not auto-update.

**Why**: a body claiming a column lives in table A when a migration moved it to table B, or claiming a flag defaults to `0.5s` when the real default is `0.05s` (off by 10x), reads as authoritative and misleads. Verify before you write.

### Rule 1.6: Issue templates use structured forms, not freeform markdown

Use form templates that enforce structure mechanically at filing time, not freeform markdown templates that only suggest it. Required fields: status date, priority, complexity. Required structured fields per template kind (goal + acceptance for features; symptom + expected + reproduce + acceptance for bugs).

**Forms gotcha**: dropdown selections produce TEXT in the issue body under `### <field label>` headings; they DO NOT auto-apply as labels. To make dropdowns actually apply matching labels, add a labeler workflow that triggers on issue-opened, extracts the value under each heading, validates against the known label set, and applies the matching label.

**Why**: forms make filing discipline structural rather than suggestive. The labeler gotcha is easy to miss; the dropdowns look like they should label the issue, and they do not.

### Rule 1.7: Roadmap status colors

When the README carries a status-colored roadmap diagram, give it one node per epic, open and closed alike, and a shared legend diagram first. A node's color moves with state in the same change that opens, starts, or closes the epic; the issue body, prose, node label, and class must all describe the same state.

A consistent, named palette (one fill per lifecycle state: done / active / in-review / next / partial / todo, text `#FFFFFF`) keeps the diagram legible. A gate fails when the first diagram block is not the legend, a class is outside the palette, or an epic-labeled issue has no node in any diagram. Run it; it must print OK.

## 2. Labels

### Rule 2.1: Brutal-minimum label set

The canonical set is small. Labels exist only to mechanically partition the issue space; everything else lives in the issue body or in native tracker primitives (issue state, milestones, project boards). A workable minimum:

| Label | Use |
|---|---|
| `bug` | Something ships incorrectly |
| `enhancement` | New feature, refactor, or design proposal |
| `epic` | Aggregation parent of related issues; mechanically excluded from "missing kind" check |
| `priority: high` | Critical / release-gating / actively-blocking. Absence means "do when you can." |
| `good first issue` | Newcomer-friendly; trackers often render this specially |

Kind is determined at filing time (the feature template applies `enhancement`, the bug template applies `bug`). Maintainers add the rest post-filing where warranted.

**What is not a label here:**

- **Complexity.** Read the diff. If you need a label to tell readers the issue is hard, your prose is failing.
- **Priority gradient.** `priority: medium` / `low` collapse to "absence of `priority: high`." If the gradient does not change behaviour, it is decoration.
- **Topical categorisation.** That is composition, not type. Encode it in the body or a milestone.
- **Status / lifecycle** (`wishlist`, `blocker`, `awaiting release`, `released-in: vX`). Status belongs to tracker-native primitives, not labels.

**Why this size**: each surviving label has at least one mechanical reason it cannot fold into the body. Three lenses converge on the set: *cut mercilessly* (cut even fine things that do not earn their place); *classify by type, not status* (route status / lifecycle / release-tracking to native primitives); *prose over labels* (if you need a label to convey something, your prose is failing). Labels exist only for what mechanical tools must partition on.

### Rule 2.2: Threshold for adding a new label

Before adding the next label, ask: does it have at least 3 expected open carriers (now or within the next planning cycle)? AND does it survive all three lenses above? Would you ship it or delete it? Is it a type/axis, or status/lifecycle/composition pretending to be a type? Does it mechanically partition the issue space in a way a filter or CI script must use, or is it commentary that belongs in the body? If any lens fails, fold it into the body. A one-line note there is as discoverable as a single-carrier label without the dropdown clutter.

**Why**: single-carrier labels are footnotes pretending to be axes. Sprawling label sets stop being navigable past about 10.

### Rule 2.3: Consistent color palette

Draw label colors from one published, named palette with strong semantic associations, so labels render coherently in any view that supports colour. Pick the hue by meaning (red = urgent/blocking, blue = active work, purple = aggregation, green = newcomer-friendly/shipped), and reserve the rest of the palette for any later additions by the same semantic grouping.

### Rule 2.4: Label deletion is destructive on closed issues

Deleting a label removes it from every issue that ever bore it, including closed ones. Rename instead of delete when historical association matters.

**Why**: closed issues are the project's audit trail. A `phase-1` label on closed refactor issues told a later reader "this was Phase 1 of that refactor"; deleting it removes that context, renaming preserves it. Prefer rename over delete for labels with closed carriers. Brutal trims that delete closed-carrier labels should be a deliberate, documented choice, acceptable when the information still lives in release notes, the changelog, and merge commits.

## 3. Pull requests

### Rule 3.1: One focused change per PR

A PR ships one cohesive change. If the diff spans two unrelated concerns, split. Critic-fix iterations on the same change belong in the same PR (separate commits, same branch). Different concerns belong in different PRs even if they touch the same files.

### Rule 3.2: Changelog required for non-trivial changes

Projects that maintain a changelog require an entry per non-trivial PR. "Non-trivial" means production source touched. Trivial means docs / tests / scripts / configuration only. A mechanical pre-commit + CI check enforces this; opt out with a `[no-changelog]` token in the commit message body when the change genuinely does not warrant an entry.

**Why**: PR descriptions live in the merge graph; the changelog lives in the release. Without enforcement, source ships ahead of its description.

### Rule 3.3: Critic-fix loop on every non-trivial PR

After opening a PR, do a self-critic pass: read your own diff as a reviewer would, find issues, fix them in additional commits on the same branch. Iterate until critique surfaces nothing new. Commit naming: `critic-fix(<scope>): <what was wrong>`. The history shows the iteration; the PR diff shows the converged result.

**Why**: mechanical edits without re-reading the surrounding paragraph create new bugs. An edit that injects a reference inside a sentence saying "this is independent" creates a contradiction. Critic-fix loops catch the self-introduced bugs the original change did not have.

### Rule 3.4: PR head is never the canonical branch for release merges

When merging a release branch into the canonical branch, the PR head is a dedicated `release/v<X.Y.Z>` branch, not the canonical working branch. Auto-delete-on-merge would otherwise kill a long-lived branch.

**Why**: the auto-delete-branch-on-merge feature is useful for short-lived feature branches and destructive for long-lived development branches. Always interpose a release branch as the head.

## 4. Branches

### Rule 4.1: Branch naming

- `fix/<issue>-<topic>` for bug fixes (e.g. `fix/284-error-page-filter`)
- `feat/<topic>` for features
- `chore/<topic>` for tooling, infrastructure, non-functional cleanup
- `docs/<topic>` for documentation-only changes
- `refactor/<topic>` for structural reorganisation
- `release/v<X.Y.Z>` for release-prep branches (PR head per Rule 3.4)

Issue-anchored prefixes when an issue exists; otherwise topic-anchored.

### Rule 4.2: Branch from canonical base

Branch from the current tip of the canonical base branch (the one the PR will target). The safe form is to fetch the base and branch from the fetched ref, not from a stale local copy, which creates merge conflicts later.

### Rule 4.3: Issue-first workflow

For every bug fix: file the issue first, then branch. The branch name carries the issue number; the PR auto-links via `Closes #N`. For features, an issue is optional but recommended when scope is non-trivial.

**Why**: the issue is the audit trail. A branch + PR without an issue has no place for the symptom / repro / acceptance discussion; the PR body can hold that but does not survive a squash-merge as well as an issue does.

## 5. Commits

### Rule 5.1: No AI attribution in committed text

Generated content carries no AI-tool attribution in any committed text. The standard is "would a colleague reading this guess a tool wrote it?" If yes, remove it. This is tool-agnostic: it covers every coding assistant and its vendor, not any single one. Specifically forbidden:

- Any AI co-author or "generated with" line in commit messages or PR descriptions. In particular, strip the trailers these tools emit: `Co-Authored-By: Claude` and "Generated with Claude Code" (Claude / Anthropic), `Co-Authored-By: Cursor` / "Generated by Cursor" (Cursor), "Co-authored-by" / "Generated with" lines from Codex / ChatGPT / GPT (OpenAI), GitHub Copilot, and Gemini and Antigravity (Google). Several of these reinsert the trailer automatically even after being told not to, and do not honor editor- or settings-level attribution toggles, so removing them cannot rely on configuration alone. # style-check: allow
- The exact emitted forms to delete on sight: a `🤖 Generated with Claude Code` line (robot emoji plus a tool link), a `Co-Authored-By: Claude <noreply@anthropic.com>` or model-named (`Claude Opus`, `Claude Sonnet`, `GPT-4o`) co-author, any no-reply or bot email in a co-author trailer, and tool-named `Assisted-by:`, `Generated-by:`, or `Authored-by:` trailers. The config toggles (`attribution`, `includeCoAuthoredBy`) do not bind tools that ignore them and are overridden in practice, so they do not replace stripping the line. # style-check: allow
- Promotional or assistive phrasing that credits tooling: "powered by", "made with", "built with", "with AI assistance", "AI-assisted", "AI-generated", "generated by AI", "with the help of", "courtesy of", "thanks to", "via", or "using" followed by a tool or vendor name, anywhere in a message, PR body, branch name, or comment.
- The name of any AI tool or vendor (Claude, Anthropic, Cursor, Codex, OpenAI, ChatGPT, GPT, Copilot, Gemini, Antigravity, or any other), or the words "AI", "LLM", "agent", "assistant", "automated", "machine-generated", "co-pilot", "pair-programmer" (when no human pair existed), or any synonym, in commits / PRs / branch names / file names / code comments that could end up in front of a colleague.
- Self-references in casual phrasing ("as an AI", "the agent did X", "automated cleanup", a trailing "generated" or "powered by"). # style-check: allow
- AI-tell stylistic patterns: emoji used as a signature/flourish (notably the 🤖 robot and ✨ sparkle), "Here's a quick summary:" preludes, gratuitous emoji-prefixed bullets, "I'll now..." / "Let me..." preambles, a structured summary/test-plan block appended to every body when the project does not already use that shape. # style-check: allow
- Watermarks: zero-width characters, unusual unicode spaces, hidden HTML comments naming a tool, branch suffixes like `-ai` / `-bot` / a tool name.

Anything you would recognise as an AI tell, even if not listed, is out. The work must read as entirely human-authored. # style-check: allow

Because several assistants reinsert attribution on their own, telling the tool not to is not enough, and a project's settings toggle does not bind tools that ignore it. A commit-message hook is REQUIRED, not optional, and must be installed per clone (hooks live in `.git/` and are not cloned) via a tracked `core.hooksPath` or by copying the hook into `.git/hooks/commit-msg`. Install the style hook described in Section 7. Rule 5.1 + Rule 5.2 + the hook together close the loop: the rule states intent, the hook refuses violations at commit time, so no commit reaches `git push` carrying either failure.

### Rule 5.2: No em dashes in committed text

The em dash (U+2014) is a recognisable writing tell. Replace it with commas, periods, colons, semicolons, or restructure the sentence. Apply to commit messages, PR descriptions, code comments, issue bodies, documentation, and README content: everything that lands in the repo or in front of a colleague. En dashes (U+2013) and hyphens (U+002D) are fine; only the em dash is forbidden. Enforce it with the commit-message hook for messages, and a `pre-commit` byte check over staged diffs for file content.

### Rule 5.3: Verify after an amend with no message edit

A no-edit amend keeps the previous commit's message verbatim. After any such amend, view the head commit to confirm the message still describes the new tree accurately. If the staged change made the previous message wrong, rewrite it instead.

**Why**: silent message staleness is one of the easiest commit-history bugs to introduce. The no-edit amend anchors the old message, which then lies about content that has since changed.

## 6. Remotes

Pushes follow the usual conventions: short-lived feature branches push freely; canonical branches land only via merge of an approved PR.

**Some remotes are review-gated.** A push to a review-gated or audited remote bypasses the review it exists to enforce. Inspect the remote URL before pushing; do not push to such a remote without explicit authorization, even for a small fix. Local commits, branches, fetches, pulls, and rebases against it are fine; only the push is gated. When in doubt about whether a remote is gated, treat it as gated and ask.

## 7. Mechanical enforcement

A repo that adopts these rules should ship a mechanical backstop, because discipline scales with attention and hooks do not:

- **Body-drift scan**: a scheduled script that greps open issue bodies for renamed paths, phantom paths, stale cross-refs, stale schema claims, and label drift. Output goes into a single tracking issue updated on each run.
- **Changelog gate**: a pre-commit hook + CI gate that refuses commits / PRs touching production source without a changelog entry.
- **Issue forms with labeler**: structured form templates + a workflow on issue-opened that translates form dropdown values into matching labels.
- **Style-tell commit-msg hook**: a `commit-msg` hook that refuses messages containing em dashes (U+2014), the forbidden AI-attribution phrases from Rule 5.1, or AI-signature emojis. Keep it portable (no PCRE dependency). Install per clone by symlink or copy into `.git/hooks/commit-msg`, or point `core.hooksPath` at a tracked hooks directory. Strip comment lines and the diff-scissors block before checking so notes in `# ...` lines are not penalised.

A disciplined author following Rule 5.2 can still push a commit whose message contains an em dash, because nothing at the commit boundary stops it without a hook. A short `commit-msg` hook prevents that entire failure class at write time, after which `git push` cannot carry a violation regardless of who or what wrote the message. The hook is the only tool-agnostic backstop: it runs on every commit no matter which assistant produced the text.

## 8. CI workflows and truthful badges

### Rule 8.1: One workflow file per concern, one badge per workflow

Each CI concern (style/gates, and each build-or-test platform) is its own workflow file with a unique name. A README badge points at that one workflow's status endpoint, so the badge tracks exactly one job and is truthful.

Do NOT use a single multi-job workflow with several cosmetically-labeled badges that all point at the same workflow. The workflow-status endpoint reports whole-workflow status, so every such badge renders the same result: a failure in any one job turns all of them red, and none tracks its named platform. That is a lying badge.

### Rule 8.2: Use the native per-workflow badge, plus a license badge

Use the tracker's native per-workflow badge (it reflects the real status of that one workflow), not a third-party status badge with a cosmetic label. Add a static license badge that links to the repo's `LICENSE`, with the label matching the actual license.

### Rule 8.3: Add a platform job and badge ONLY when that platform is genuinely possible

A badge is a claim; only claim a platform the repo can actually build or test on. An absent badge is honest; a red-or-fictional badge is not. Decide possibility from the repo's topology:

- UI builds and tests run on the platform that hosts the UI runner only. Do not add a badge for a platform that cannot run that UI.
- A given OS badge belongs only when the product builds on that OS's toolchain.
- When a platform can build but not run the full suite, the workflow is a build gate, not a test gate. Say so in a header comment so the green badge is not read as "tests pass" when it means "compiles."

### Rule 8.4: Triggers and permissions are uniform across the split

Every workflow uses the same trigger surface so the badges refresh together (push to the canonical branch, pull request, and manual dispatch). Keep permissions least-privilege (read-only, plus the one extra scope a specific gate needs). The commit-message attribution gate (Rule 5.1) lives in the style workflow and needs full history on checkout plus the PR base/head SHAs to scan the commit range.

## Acceptance check

A repo conforms when: (1) every open issue body has a dated status block, no line-number anchors, no phantom paths, and no stale cross-refs; (2) the label set is minimal, every label survives the three lenses, and colors come from one named palette; (3) each PR is one focused change with a changelog entry when non-trivial; (4) branches follow the naming scheme and branch from a fresh canonical base; (5) `git log` shows no AI attribution and no em dashes in any committed text, with a `commit-msg` hook installed to enforce it; (6) no push to a review-gated remote happened without authorization; and (7) each CI badge points at exactly one named workflow and claims only a genuinely-possible platform. Mechanical backstops (body-drift scan, changelog gate, labeler, style hook) are installed, and the hooks are installed per clone.

## Companion rules

- `no-shortcuts-first-principles.md`: the ethic this specializes. A phantom path, a stale cross-ref, a lying badge, and a stale amended message are all hidden debt that reads as truth; this rule is the issue-tracker and git-history application of "disclosed limits, never hidden debt."
- `proof-discipline.md`: a badge is a correctness claim; Rule 8.3 is "do not claim a platform you cannot prove," the CI form of "no unlabeled `correct`."

## Why this exists

An issue tracker and a git history are read by people who were not in the room. They age into fiction the moment a path moves, a dependency closes, a default changes, or a badge points at the wrong job, and nothing in the bare tools stops that drift. These conventions keep the written record true to the code: dated status, verified references, minimal labels, one-concern PRs, honest badges, and a commit history that reads as human-authored. The mechanical backstops make the discipline survive a tired author, because a hook does not get tired.
