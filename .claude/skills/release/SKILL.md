---
name: release
description: Cut a MythicLoot release from main — stamp the changelog, build a clean distributable zip, tag, and publish a GitHub release using the version already set in the .toc. Use when the user wants to release, ship, publish, or tag a new version of the addon.
---

# Release MythicLoot

Cut a new release of the addon **from `main`**. The version shown in the app's
footer is read at runtime from `MythicLoot/MythicLoot.toc` (`## Version:`) — that
line is the **single source of truth**.

This skill does **not** bump the version. By convention the version is bumped
**beforehand in a separate chore PR** (e.g. "chore: bump version to 1.1.0") that
merges to `main`, so the bump is reviewable on its own. This skill releases
whatever version `main`'s `.toc` currently declares: stamp the changelog, build,
tag, publish. Takes no argument.

## Preconditions — check, then STOP if any fail

1. **On `main`, up to date with origin.** `git branch --show-current` is `main`;
   `git fetch` then confirm `main` is level with `origin/main`. Releasing from a
   feature branch tags a commit that may not survive a squash-merge. If not on
   `main`, tell the user to merge first.
2. **Clean working tree.** `git status --porcelain` is empty.
3. **Version is bumped and not yet released.** Read `## Version: X.Y.Z` from the
   `.toc`. If a tag `vX.Y.Z` already exists (`git tag -l vX.Y.Z`), the version
   wasn't bumped — STOP and tell the user to land the version-bump chore PR first.
4. **`gh` is authenticated.** `gh auth status`.

## Steps

1. **Read the release version** `X.Y.Z` from the `.toc` (do not change it).

2. **Today's date** via `date +%F` (never hardcode — this runs on other days).

3. **Resolve the release notes.** In `CHANGELOG.md`:
   - If there's a `## Unreleased` section, its body is the notes; you'll stamp the
     heading in step 5.
   - Else if there's already a `## vX.Y.Z …` section, use that body (already
     stamped — skip step 5's commit).
   - If neither exists, STOP — a release with no notes is almost always a mistake.

4. **Confirm before any outward-facing action.** Show the user and wait for a
   clear go-ahead: the version `vX.Y.Z`, the notes to publish, and that a tag +
   public GitHub release will be created. Tags and releases are hard to undo, so
   this checkpoint is required.

5. **Stamp the changelog** (only if it still says `## Unreleased`): rename that
   heading to `## vX.Y.Z — YYYY-MM-DD`, then commit just that file:
   `git commit -m "Release vX.Y.Z"` (end with the standard Co-Authored-By trailer)
   and `git push`. The version bump itself already landed via the chore PR, so this
   is the only commit the release makes — a one-line changelog stamp.

6. **Build the zip**: run `.claude/skills/release/package.sh`. Confirm the listing
   is only `MythicLoot/` (the `.lua` + `.toc`), no `.DS_Store`, no docs.

7. **Syntax-check** like CI, so a broken build never ships:
   `find MythicLoot -name '*.lua' -print0 | xargs -0 -n1 luac -p`
   (use `luac5.1` if present). Stop on any error.

8. **Tag and push**: `git tag vX.Y.Z && git push origin vX.Y.Z` (tags `main`'s HEAD).

9. **Publish the GitHub release** with the zip attached and the changelog body as
   notes: `gh release create vX.Y.Z MythicLoot.zip --title "vX.Y.Z" --notes "<body>"`.

10. **Report**: the version, the release URL, and that the zip (git-ignored) is now
    attached to the release.

## Notes

- To bump the version, don't do it here — open a chore PR that edits `## Version:`
  in `MythicLoot.toc` (the footer reads it at runtime), get it merged to `main`,
  then run this skill.
- The zip is intentionally git-ignored (`*.zip`); it exists only as a release asset.
- Leave `## Interface:` alone — that's the WoW client build, not the addon version.
