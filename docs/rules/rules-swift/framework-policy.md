# Framework Policy (MANDATORY, ZERO TOLERANCE)

This codebase targets Apple platforms exclusively. Every suggestion, comparison,
recommendation, citation, and dependency stays inside Apple's own SDKs (SwiftUI,
UIKit, AppKit, Foundation, and the rest of Apple's frameworks) and the
Swift-native ecosystem. This is not a default to be argued out of. It is a hard
boundary that holds in code, comments, documentation, commit messages, reviews,
and conversation alike.

## The mandate

- **Apple frameworks only.** Suggest, compare against, recommend, or cite Apple's
  own SDKs and the Swift / Apple-native ecosystem, and nothing else. Swift-native
  community libraries are acceptable. Non-Apple product stacks are not.
- **Never name a non-Apple UI or cross-platform stack.** Do not introduce one as a
  dependency, do not suggest one, do not compare against one, do not validate a
  choice by pointing at one, and do not mention one as an aside or as "this is what
  others do." This holds for every Android, web, mobile, or cross-platform UI
  toolkit without exception. The prohibition is stated as a category on purpose:
  do not enumerate the banned stacks, do not name them at all. "I only cited it as
  neutral corroboration" is not a defence.
- **The only exception is Linux.** When the target is genuinely Linux, use native
  **C or C++** only. No other language, runtime, or framework is acceptable on
  Linux.

## Concept versus rival framework: the exact line

Ecosystem-neutral academic and HCI theory may be referenced to explain a concept:
the architecture and interaction-design literature, the separation-of-concerns and
testability patterns, the layering models, and the like. The line is exact:

- **Allowed:** explaining a concept by way of vendor-neutral theory.
- **Forbidden:** naming a rival framework to adopt, to compare against, or to be
  validated by.

When an idea's most famous instance lives in a non-Apple stack, make the point
with an Apple-native or vendor-neutral example, or drop the example. Never reach
for the banned stack just because it is the canonical illustration.

## Why this exists

A single non-Apple reference, even an offhand one, reframes the codebase as
platform-agnostic and invites drift in dependencies, comparisons, and reviewer
expectations. Holding the boundary at the level of what we are even willing to
name keeps every decision anchored to Apple's frameworks and the Swift-native
ecosystem, which is the whole point of the project.

## Acceptance check

A change conforms when: (1) no non-Apple UI or cross-platform stack is named in
code, comments, docs, or commit text; (2) every new dependency is an Apple SDK or
a Swift-native library; (3) any non-Apple-targeted comparison or "what others do"
aside is absent; and (4) the only non-Swift code present targets Linux and is
native C or C++. A change that names a rival stack anywhere, even as corroboration,
fails this rule.
