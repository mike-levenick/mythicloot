---
name: release
description: Cut a MythicLoot release from main. If the version still needs bumping it opens the chore PR and stops; otherwise it stamps the changelog, builds a clean distributable zip, tags, and publishes a GitHub release. Use when the user wants to release, ship, publish, or tag a new version of the addon.
---

# Release MythicLoot

Cut a new release of the addon **from `main`**. The version shown in the app's
footer is read at runtime from `MythicLoot/MythicLoot.toc` (`## Version:`) — that
line is the **single source of truth**.

Version bumps go through a reviewable **chore PR**, never a direct commit to
`main`. This skill is two-phase and decides which phase applies automatically:

- **Phase A — bump needed:** the version in the `.toc` is already released (a tag
  for it exists). The skill opens the version-bump chore PR for you and stops.
  Merge it, then run the skill again.
- **Phase B — ready to ship:** the `.toc` version isn't tagged yet (the bump
  already merged). The skill stamps the changelog, builds, tags, and publishes.

Optional argument = the bump for Phase A: `patch` (default), `minor`, `major`, or
an explicit `X.Y.Z`. Ignored in Phase B.

## Preconditions — check, then STOP if any fail

1. **On `main`, level with origin.** `git branch --show-current` is `main`;
   `git fetch --tags` then confirm `main` equals `origin/main`. Releasing from a
   feature branch tags a commit that may not survive a squash-merge.
2. **Clean working tree.** `git status --porcelain` is empty.
3. **`gh` is authenticated.** `gh auth status`.

## Decide the phase

Read `## Version: X.Y.Z` from the `.toc`. Check `git tag -l vX.Y.Z`:

- **Tag exists → Phase A** (the current version is already out; a bump is due).
- **No tag → Phase B** (the bump already landed; this version is unreleased).

## Phase A — open the bump chore PR

1. Compute the new version from the argument: `patch` → Z+1 · `minor` → Y+1,Z=0 ·
   `major` → X+1,Y=0,Z=0 · explicit `X.Y.Z` → verbatim. Default `patch`.
2. Confirm the new version with the user.
3. From `main`: `git checkout -b chore/bump-version-<new>`, set `## Version:` to the
   new version in the `.toc`, commit `chore: bump version to <new>` (with the
   standard Co-Authored-By trailer), push, and `gh pr create --base main` with a
   short body explaining the footer reads this line at runtime.
4. **Stop.** Tell the user to review and merge the PR, then re-run `/release` to
   publish. Do not tag or build in this phase.

## Phase B — stamp, build, tag, publish

1. **Version** `X.Y.Z` is the `.toc` value (don't change it). **Date** via
   `date +%F` (never hardcode — runs on other days).
2. **Resolve release notes** in `CHANGELOG.md`: the `## Unreleased` body, or an
   existing `## vX.Y.Z …` body if already stamped. If neither exists, STOP — a
   release with no notes is almost always a mistake.
3. **Confirm before publishing.** Show the user `vX.Y.Z`, the notes, and that a tag
   + public GitHub release will be created; wait for a clear go-ahead. Tags and
   releases are hard to undo, so this checkpoint is required.
4. **Stamp the changelog** (only if still `## Unreleased`): rename to
   `## vX.Y.Z — YYYY-MM-DD`, commit just that file `Release vX.Y.Z` (Co-Authored-By
   trailer), and `git push`. This is the only commit the release makes.
5. **Build the zip:** run `.claude/skills/release/package.sh`; confirm the listing
   is only `MythicLoot/` (the `.lua` + `.toc`), no `.DS_Store`, no docs.
6. **Syntax-check** like CI: `find MythicLoot -name '*.lua' -print0 | xargs -0 -n1 luac -p`
   (use `luac5.1` if present). Stop on any error.
7. **Tag and push:** `git tag vX.Y.Z && git push origin vX.Y.Z` (tags `main`'s HEAD).
8. **Publish:** `gh release create vX.Y.Z MythicLoot.zip --title "vX.Y.Z" --notes "<body>"`.
9. **Report** the version, the release URL, and that the zip (git-ignored) is now
   attached to the release.

## Notes

- The zip is intentionally git-ignored (`*.zip`); it exists only as a release asset.
- Leave `## Interface:` alone — that's the WoW client build, not the addon version.
