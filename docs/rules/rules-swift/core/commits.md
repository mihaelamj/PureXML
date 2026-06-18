# Git Commit Framework

**Status: house convention for committed text.** Every commit follows the Conventional Commits specification: imperative mood, one logical change per commit, a message that communicates the what, the why, and the impact for both human readers and automated tooling. This is the companion to `file-naming.md` (the same discipline applied to committed filenames) and to `no-shortcuts-first-principles.md` (a commit that hides what it actually did is a shortcut).

## Core rules

### Rule 1: Commit format

Use this exact format:

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

- MUST use lowercase for the type.
- MUST use present tense, imperative mood ("add", not "added").
- MUST NOT end the description with a period.
- MUST limit the first line to 72 characters.

### Rule 2: Commit types

Select the correct type:

- `feat`: new feature or functionality.
- `fix`: bug fix or error correction.
- `docs`: documentation changes only.
- `style`: code style/formatting (no logic change).
- `refactor`: code restructuring (no behavior change).
- `perf`: performance improvements.
- `test`: test additions or corrections.
- `build`: build system or dependencies.
- `ci`: CI/CD configuration changes.
- `chore`: maintenance tasks.

### Rule 3: Breaking changes

Indicate breaking changes:

- MUST add `!` after the type/scope for breaking changes.
- MUST include a `BREAKING CHANGE:` footer.
- MUST explain the migration path.

### Rule 4: Commit scope

Include a relevant scope:

- Use a component/module name, a feature area, or a layer.
- Keep scopes consistent across the project.
- Omit the scope only when the change is truly global.

## Commit type decision tree

```
What kind of change are you making?
|- Adding new capability?
|   |- User-facing feature? -> feat
|   |- Developer tool? -> build/chore
|   +- Test coverage? -> test
|- Fixing something broken?
|   |- Bug in code? -> fix
|   |- Typo in docs? -> docs
|   +- Test failure? -> test/fix
|- Changing existing code?
|   |- Improving performance? -> perf
|   |- Restructuring code? -> refactor
|   |- Formatting only? -> style
|   +- Updating dependencies? -> build
+- Project maintenance?
    |- CI/CD changes? -> ci
    |- Documentation? -> docs
    +- Other tasks? -> chore
```

## Commit message patterns

### Pattern 1: Feature commits

```
# New features state a clear user benefit
feat(auth): add OAuth2 authentication support

# Include implementation details in the body
feat(api): implement rate limiting for API endpoints

Adds configurable rate limiting:
- 100 requests per minute for anonymous users
- 1000 requests per minute for authenticated users
- Customizable limits per API key

Closes #234
```

### Pattern 2: Bug fix commits

```
# Describe what was broken and now works
fix(parser): handle empty input without crashing

# Reference issue numbers
fix(ui): correct button alignment on mobile devices

The submit button overlapped with the cancel button on
screens smaller than 375px. Added proper flex spacing.

Fixes #456
```

### Pattern 3: Breaking change commits

```
# Use ! and a BREAKING CHANGE footer
feat(api)!: change authentication from sessions to tokens

BREAKING CHANGE: the API now requires bearer-token authentication.
Session-based auth has been removed. Update clients to send an
Authorization header with the token.

Migration guide: docs/migration/v2.md
```

### Pattern 4: Refactoring commits

```
# Explain why, not just what
refactor(database): extract query builder into a separate type

Improves testability and reduces coupling between the
repository and database layers. No functional changes.

# Keep behavior identical
refactor(utils): use native collection methods instead of a helper

Removes a dependency for collection operations.
All tests pass without modification.
```

### Pattern 5: Documentation commits

```
# Be specific about what was documented
docs(readme): add installation instructions for a fresh machine

# Include scope for API docs
docs(api): document rate-limiting headers and status codes
```

### Pattern 6: Performance commits

```
# Include metrics when possible
perf(search): optimize full-text search query

Reduces search time from ~500ms to ~50ms by adding a
compound index on (title, content, created_at).

Benchmark results:
- Before: 487ms avg (n=1000)
- After: 52ms avg (n=1000)
```

## Commit scope guidelines

Common scope patterns:

- Component name: `(Button)`, `(Modal)`, `(Form)`.
- Feature area: `(auth)`, `(payment)`, `(search)`.
- Layer: `(api)`, `(db)`, `(ui)`, `(service)`.
- File type: `(config)`, `(types)`, `(tests)`.

Omit the scope only for truly global changes (project-wide dependency updates, global configuration, cross-cutting refactors).

For a multi-file change, use the most specific common scope:

```
# Changed files all under the auth area
feat(auth): add session timeout handling

# Changed files span many unrelated areas
refactor: update imports to use path aliases
```

## Commit body guidelines

Include a body when the change requires explanation: multiple issues addressed, breaking changes, available performance metrics, complex implementation details, or external references.

Body format rules:

- Separate the body from the subject with a blank line.
- Wrap the body at 72 characters.
- Use bullet points for multiple items.
- Explain why, not just what.

```
fix(cache): prevent memory leak in the LRU cache

- Add proper cleanup on cache eviction
- Use weak references for cached objects
- Add a memory-limit configuration option

The previous implementation held strong references to evicted
items, preventing reclamation. This change ensures proper memory
management while keeping O(1) operations.

Fixes #789
```

## Commit footer patterns

### Issue references

```
fix(api): validate input before processing

Fixes #123        # Closes the issue
Closes #456       # Also closes the issue
Resolves #789     # Also closes the issue
See #101          # References without closing
Related to #102   # References without closing
```

### Co-authors

Credit every human contributor:

```
feat(ui): implement dark mode toggle

Pair-programmed the styling architecture and state management.

Co-authored-by: Jane Doe <jane@example.com>
Co-authored-by: Bob Smith <bob@example.com>
```

### Review references

```
refactor(engine): simplify state-machine logic

See the detailed discussion in PR #234 about the
approach and the alternatives considered.

Reviewed-by: Alice Johnson <alice@example.com>
```

## No tool attribution in committed text (MANDATORY)

Committed text is authored by the people who made the change. Commit messages, PR descriptions, branch names, code comments, and any other text that lands in the repo name the human contributors and nothing else. The standard is one question: would a colleague reading this guess a tool wrote it? If yes, remove it. This is tool-agnostic, covering every coding assistant and its vendor, not any single one.

Specifically forbidden in any commit message, PR description, branch name, file name, or code comment:

- A `Co-Authored-By:` trailer, a "Generated with" / "Generated by" line, or any "created by" attribution that names a coding assistant or its vendor. In particular, strip the trailers these tools emit: `Co-Authored-By: Claude` and "Generated with Claude Code" (Claude / Anthropic), `Co-Authored-By: Cursor` / "Generated by Cursor" (Cursor), "Co-authored-by" / "Generated with" lines from Codex / ChatGPT / GPT (OpenAI), GitHub Copilot, and Gemini and Antigravity (Google). Several of these reinsert the trailer automatically even after being told not to, and do not honor editor- or settings-level attribution toggles, so removing them cannot rely on configuration alone. # style-check: allow
- The exact emitted forms to delete on sight: a `🤖 Generated with Claude Code` line (robot emoji plus a tool link), a `Co-Authored-By: Claude <noreply@anthropic.com>` or model-named (`Claude Opus`, `Claude Sonnet`, `GPT-4o`) co-author, any no-reply or bot email in a co-author trailer, and tool-named `Assisted-by:`, `Generated-by:`, or `Authored-by:` trailers. The config toggles (`attribution`, `includeCoAuthoredBy`) do not bind tools that ignore them and are overridden in practice, so they do not replace stripping the line. # style-check: allow
- Promotional or assistive phrasing that credits tooling: "powered by", "made with", "built with", "with AI assistance", "AI-assisted", "AI-generated", "generated by AI", "with the help of", "courtesy of", "thanks to", "via", or "using" followed by a tool or vendor name, anywhere in a message, PR body, branch name, or comment.
- The name of any AI tool or vendor (Claude, Anthropic, Cursor, Codex, OpenAI, ChatGPT, GPT, Copilot, Gemini, Antigravity, or any other), or the words "AI", "LLM", "agent", "assistant", "automated", "machine-generated", "co-pilot", or "pair-programmer" (when no human pair existed), or any synonym or euphemism for tooling.
- Self-referential phrasing ("as an AI", "the agent did X", "automated cleanup") and any coded wink at tool authorship. # style-check: allow
- Stylistic tells: emoji used as a signature or flourish (notably the 🤖 robot and ✨ sparkle), a trailing "generated" / "powered by", or watermarks (zero-width characters, hidden comments naming a tool, `-ai` / `-bot` / tool-name branch suffixes). # style-check: allow

Co-author trailers credit only the humans who collaborated on the change. The history reads as human-authored because the change is the contributors' work.

Because several assistants reinsert attribution on their own, telling the tool not to is not enough. A project-level commit-message hook is REQUIRED, not optional: install it per clone (hooks live in `.git/` and are not cloned) via a tracked `core.hooksPath` or by copying the hook into `.git/hooks/commit-msg`. The hook is the only tool-agnostic enforcement that holds no matter which assistant wrote the message. See `git-discipline.md` Rule 5.1 for the same prohibition across the broader git surface.

## Commit validation checklist

Before committing, verify:

- [ ] Type is correct (`feat`/`fix`/`docs`/etc.).
- [ ] Scope reflects the affected area.
- [ ] Description is in imperative mood.
- [ ] Description is under 72 characters.
- [ ] No period at the end of the description.
- [ ] Breaking changes marked with `!`.
- [ ] `BREAKING CHANGE:` footer present if needed.
- [ ] Body explains why, not just what.
- [ ] Body wrapped at 72 characters.
- [ ] Issue references use the correct keywords.
- [ ] Co-authors are humans, credited properly.
- [ ] No tool/assistant attribution anywhere in the text.
- [ ] Commit is atomic (one logical change).
- [ ] All tests pass.
- [ ] No debug code or stray logging.

## Squash fixups before sharing

A shared history is a sequence of logical changes, not a transcript of how you got there. Squash `fixup!`/`wip`/`oops` commits into the commit they belong to before pushing or opening a PR. One logical change is one commit.

## Common mistakes to avoid

### DON'T: use past tense

```
# WRONG
feat(auth): added login functionality

# RIGHT
feat(auth): add login functionality
```

### DON'T: be vague

```
# WRONG
fix: fix bug
chore: update stuff
refactor: changes

# RIGHT
fix(parser): handle null input in the JSON parser
chore(deps): update the HTTP client from 1.4.0 to 1.5.0
refactor(auth): extract token validation into middleware
```

### DON'T: combine unrelated changes

```
# WRONG
feat(ui): add dark mode and fix login bug and update deps

# RIGHT, split into separate commits:
feat(ui): add dark mode toggle
fix(auth): resolve login redirect issue
build(deps): update the framework and toolchain
```

### DON'T: forget breaking-change notation

```
# WRONG
feat(api): change response format

# RIGHT
feat(api)!: change response format to follow the JSON:API spec

BREAKING CHANGE: API responses now use the JSON:API format.
Old format: { data: [...] }
New format: { data: [...], meta: {}, links: {} }
```

## Branch naming

Use a consistent branch-name format:

```
<type>/<ticket>-<brief-description>

# Examples:
feat/123-add-oauth-support
fix/456-resolve-memory-leak
chore/update-dependencies
release/v2.0.0
hotfix/critical-security-patch
```

Branch types mirror commit types: `feat/*`, `fix/*`, `docs/*`, `refactor/*`, `test/*`, `chore/*`.

## Companion rules

- `file-naming.md`: the same lowercase/dashed/ASCII/ISO discipline applied to committed filenames.
- `no-shortcuts-first-principles.md`: a commit message that hides what the change did, or bundles unrelated changes to look smaller, is a shortcut.

## Why this exists

A commit history is documentation that every future reader, and every automated tool, depends on. A consistent format makes the history greppable, the changelog generable, and the blame legible. The cost is a few seconds of discipline per commit; the payoff is a history that explains itself years later.
