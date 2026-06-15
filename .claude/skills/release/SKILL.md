---
name: release
description: Cut a MythicLoot release — bump the addon version, stamp the changelog, build a clean distributable zip, tag, push, and publish a GitHub release. Use when the user wants to release, ship, publish, or cut a new version of the addon.
---

# Release MythicLoot

Cut a new release of the addon. The version shown in the app's footer is read at
runtime from `MythicLoot/MythicLoot.toc` (`## Version:`) — that `.toc` line is the
**single source of truth**; bumping it is all that changes the displayed version.

The argument (optional) is the bump: `patch` (default), `minor`, `major`, or an
explicit `X.Y.Z`. Examples: `/release minor`, `/release 1.2.0`.

## Preconditions — check, then STOP if any fail

1. **Run from `main` with the feature already merged.** Tags must point at a commit
   that survives on `main` — tagging a feature branch that later squash-merges
   leaves the tag pointing at a vanished commit. Run `git branch --show-current`.
   If not on `main`, tell the user and ask whether to continue or switch first.
2. **Clean working tree.** Run `git status --porcelain`. If dirty, stop and report
   — the release commit should contain only the version bump + changelog stamp.
3. **`gh` is authenticated.** `gh auth status`. If not, tell the user to run
   `gh auth login`.

## Steps

1. **Read the current version** from `MythicLoot/MythicLoot.toc` (the `## Version:`
   line). Compute the new version from the argument:
   - `patch` → Z+1 · `minor` → Y+1, Z=0 · `major` → X+1, Y=0, Z=0
   - explicit `X.Y.Z` → use verbatim.
   - No argument → default to `patch`.

2. **Get today's date** with `date +%F` (do NOT hardcode — this runs on other days).

3. **Confirm before any outward-facing action.** Show the user, and wait for an
   explicit go-ahead:
   - old version → new version
   - the changelog notes that will be published (the `## Unreleased` body)
   - that a tag `vX.Y.Z` and a public GitHub release will be created.
   Creating a tag + GitHub release is hard to undo, so this checkpoint is required.

4. **Bump the `.toc`**: set `## Version: X.Y.Z` to the new version.

5. **Stamp the changelog** (`CHANGELOG.md`): rename the `## Unreleased` heading to
   `## vX.Y.Z — YYYY-MM-DD`. If there is no `## Unreleased` section, warn the user
   (a release with no notes is usually a mistake) and ask whether to proceed.
   Capture that section's body — it becomes the GitHub release notes.

6. **Build the zip**: run `.claude/skills/release/package.sh`. Confirm the listing
   contains only `MythicLoot/` (the `.lua` + `.toc`), no `.DS_Store`, no docs.

7. **Syntax-check** like CI does, so a broken build never ships:
   `find MythicLoot -name '*.lua' -print0 | xargs -0 -n1 luac -p`
   (use `luac5.1` if available). Stop on any error.

8. **Commit** the bump + changelog:
   `git add MythicLoot/MythicLoot.toc CHANGELOG.md && git commit -m "Release vX.Y.Z"`
   (end the message with the standard Co-Authored-By trailer).

9. **Tag and push**: `git tag vX.Y.Z` then `git push && git push origin vX.Y.Z`.

10. **Publish the GitHub release**, attaching the zip and using the changelog
    section as notes:
    `gh release create vX.Y.Z MythicLoot.zip --title "vX.Y.Z" --notes "<changelog body>"`

11. **Report**: new version, the release URL (`gh release view vX.Y.Z --web` or the
    URL from step 10), and remind the user the zip is a build artifact (git-ignored),
    now attached to the release.

## Notes

- The zip is intentionally git-ignored (`*.zip`); it lives only as a release asset.
- Keep `## Interface:` in the `.toc` alone — that's the WoW client build, not the
  addon version.
- Heads-up on existing data: `CHANGELOG.md` currently has a `## v1.0.0 — Initial
  release` entry while the `.toc` reads `0.1.x`. The `.toc` is authoritative for the
  version sequence; mention the mismatch if it's relevant, but don't rewrite history.
