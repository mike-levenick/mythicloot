---
name: prep
description: Prep the current MythicLoot branch for review — surface in-game verification first, open as draft, run a Copilot review iteration with respectful pushback, decide whether a second pass is worth it, then flip to ready (CI runs on every PR; the user merges). Invoke as /prep.
argument-hint: (none — operates on the current branch)
---

# Prep skill (MythicLoot)

Drives a feature/fix branch from "code is written" to "ready for the user to
merge" — the same flow we run by hand (build → syntax-check → push → Copilot →
address → ready), formalized so the steps don't slip.

This is a WoW addon. The thing a desktop linter can't catch is **in-game
behavior**, so the manual-verification gate (step 2) is the heart of the skill —
never skip it silently. CI here is only a Lua 5.1 syntax check; it cannot tell you
the heart icon renders or the Voidforge lens greys out correctly.

The skill has 11 steps. **Stop after step 11 — do not monitor CI.** The user
merges when it's green, or surfaces failures themselves.

Conventions this skill assumes (all true as of 2026-06-17):
- Repo: `mike-levenick/mythicloot`, personal account, solo.
- `main` is branch-protected: PR-only, the CI "Build & Test" check required,
  linear history, squash + auto-delete-branch. **Never push to `main`.**
- CI (`.github/workflows/ci.yml`) runs on **every** PR to `main`, draft or not —
  there is no draft gate and runners are cheap, so draft is just a "not ready to
  merge yet" signal that lets Copilot's first pass land before a human looks.
- Clean-room rule (ADR 0001): never read Keystone Loot's source; API facts come
  from Blizzard's published code / warcraft.wiki.gg only. Nothing in this flow
  should pull in reference-addon code.

## Step 1 — Survey the branch

Establish what this PR is and isn't.

```bash
BRANCH=$(git rev-parse --abbrev-ref HEAD)
git fetch origin main >/dev/null 2>&1
git log --oneline origin/main..HEAD
git diff --stat origin/main..HEAD
```

- If `BRANCH == main` or there are no commits ahead of main, stop — nothing to prep.
- Check for an existing PR on this branch:
  ```bash
  PR_JSON=$(gh pr view --json number,isDraft,title,url 2>/dev/null)
  ```
  - **Exists, draft**: capture `PR_NUM`/`PR_URL`, skip step 3, resume at step 4
    (wait for Copilot) or step 5 (address) depending on whether a Copilot review
    has already landed.
  - **Exists, ready**: stop and ask — they probably want `/prep` on a different
    branch, or a manual re-request.
  - **None**: continue.

## Step 2 — In-game verification gate (mandatory)

Propose a *focused* checklist of what to smoke in-game — not a full QA pass, just
what this diff specifically risks. Derive it from the files touched:

- **`MythicLoot/UI/MainWindow.lua`** — the main window. Smoke: `/ml` to open, run
  the golden path of the changed feature, then exercise the most-likely
  regression. Frame pooling is load-bearing here, so if cells/rows/headers
  changed, **scroll + switch specs + toggle filters** and confirm no stale icon,
  star, heart, claimed-check, or tooltip leaks from a reused frame. If a new
  corner mark / texture was added, eyeball it at the cell's actual size (atlas vs
  raw texture, tint, overlap with the other three corners).
- **`MythicLoot/Data/Journal.lua`** — EJ loot reads + the runtime cache (ADR
  0007). Smoke: open on a spec whose loot isn't cached yet (watch it populate),
  then `/reload` and confirm the **warm open** paints instantly from cache and
  then reconciles. If you touched the cache stamp, switch season/build assumptions
  can't be tested, so at least confirm a stale-stamp path prunes rather than
  serves wrong loot.
- **`MythicLoot/Data/Gear.lua`** — equipped-gear / Gear Track / stat reads. Smoke
  with the diagnostics: `/ml tracks` and `/ml stats` dump live values; confirm
  they match the character sheet before trusting any hardcoded mapping.
- **`MythicLoot/Core.lua`** — slash dispatch + SavedVariables init. Smoke: each
  `/ml <subcommand>` still routes; a brand-new character (empty SavedVariables)
  opens without a Lua error.
- **`MythicLoot/MythicLoot.toc`** — load order / version. If a **new `.lua` file**
  was added to the load order, the game must be **fully restarted** (not just
  `/reload`) to discover it; note that in the checklist.
- **Voidforge / claims** (`Data/VoidCheck.lua`, claim code): verify the lens greys
  out off-spec, marks toggle via shift+right-click and the Drop Picker, and a
  fully-claimed dungeon pool reads as freshly full (exhaustion reset).

Always remind: enable `/console scriptErrors 1`, and `/reload` after each change
(full restart only when a new file joined the `.toc`).

Present via `AskUserQuestion` with two options:
- **"Verified — proceed"** (recommended): tested, or accepts the risk.
- **"Bypass — I'll verify later"**: ship the draft now, smoke after.

This is the **only** mandatory `AskUserQuestion` in the skill. Do not skip it
silently — the point is to make the user pause before opening a PR they'd regret.

## Step 3 — Commit pending work, draft PR metadata, push + open

After step 2 passes, the skill runs hands-off to the final report. **No more
`AskUserQuestion` between here and step 9** — print decisions and proceed; the
user can interject.

**Commit any pending work first.** If the tree has uncommitted changes for this
branch, commit them as one conventional-commit-shaped commit (squash-merge
collapses inside-PR commits anyway). Stage explicit paths, not `git add -A`. End
the message with the standard trailer:
`Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Pick the
prefix from the dominant change: `feat:` / `fix:` / `chore:` / `refactor:` /
`docs:`.

**Syntax-check before opening** (matches CI):
```bash
find MythicLoot -name '*.lua' -print0 | xargs -0 -n1 luac -p
```
Stop on any error — don't open a PR that CI will immediately fail.

**Compose PR metadata** from the commit history:
```bash
git log --format='%s%n%n%b' origin/main..HEAD
```
Title: one conventional-commit-shaped sentence (≤70 chars). Body: a `## Summary`
section, then a `## Test plan` checklist mirroring step 2's items. Print title +
body as a visibility checkpoint — don't prompt for confirmation.

**Label (best-effort):** map the lead commit's prefix to an existing repo label —
`feat:` → `enhancement`, `fix:` → `bug`, `docs:` → `documentation`. No matching
label (e.g. `chore:`/`refactor:`) → open without one. Don't invent labels.

**Push and open as draft:**
```bash
git push -u origin "$BRANCH" 2>&1 | tail -3
gh pr create --draft [--label <label>] \
  --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```
Capture `PR_NUM` and `PR_URL` from the output.

## Step 4 — Wait for the first Copilot review

Copilot auto-fires once on PR-open for `main`-targeting PRs (~5–7 min), works on
drafts, and does **not** re-fire on later pushes. If the PR's base is `main` and it
was just opened, the auto-fire covers it — start polling. If it's an existing PR
whose head moved since the last review, request explicitly now (same form as
step 7).

Poll in the background (`Bash` with `run_in_background: true`):
```bash
i=0
while true; do
  reviews=$(gh api repos/mike-levenick/mythicloot/pulls/$PR_NUM/reviews 2>/dev/null \
    | jq '[.[] | select(.user.login|test("copilot";"i"))] | length')
  comments=$(gh api repos/mike-levenick/mythicloot/pulls/$PR_NUM/comments 2>/dev/null \
    | jq '[.[] | select(.user.login|test("copilot";"i"))] | length')
  total=$((reviews + comments))
  if [ "$total" -gt 0 ]; then echo "Copilot landed after $((i*30))s (reviews=$reviews comments=$comments)"; break; fi
  if [ $i -ge 24 ]; then echo "Timed out after 12 min — re-check; if it never fired, request via: gh pr edit $PR_NUM --add-reviewer @copilot"; break; fi
  i=$((i+1)); sleep 30
done
```

**Bot-login quirk:** the `/reviews` endpoint returns
`copilot-pull-request-reviewer[bot]`; `/comments` returns `Copilot`. The
case-insensitive filter `test("copilot";"i")` catches both. Poll both endpoints
and OR the counts — Copilot sometimes posts only inline comments, no top-level
review (or vice versa).

When it lands, fetch and display:
```bash
# Top-level review (overview + state)
gh api repos/mike-levenick/mythicloot/pulls/$PR_NUM/reviews \
  --jq '.[] | select(.user.login|test("copilot";"i")) | "STATE: \(.state)\nSUBMITTED: \(.submitted_at)\nBODY:\n\(.body // "(none)")\n---"'
# Inline comments (with IDs we need for replies)
gh api repos/mike-levenick/mythicloot/pulls/$PR_NUM/comments \
  --jq '.[] | select(.user.login|test("copilot";"i")) | "ID: \(.id)\nFILE: \(.path):\(.line // .original_line)\nBODY: \(.body)\n---"'
```
When the head has moved past a prior review, filter by `submitted_at` so you read
the *latest* pass, not a stale one.

## Step 5 — Address the feedback

For each inline comment, decide one of three:

1. **Fix it.** Make the change, batch into commits. **Do not** reply "Fixed in
   `<SHA>`" — the commit is the documentation; ack replies are thread noise.
2. **Push back.** When Copilot is wrong (false-positive, or suggests an idiom that
   contradicts this project's — e.g. recommending shipped loot tables when ADR
   0002 says runtime-only, or reading reference-addon code which ADR 0001
   forbids), reply respectfully with evidence:
   ```bash
   gh api repos/mike-levenick/mythicloot/pulls/$PR_NUM/comments -X POST \
     -f body="<respectful, evidence-based reply>" -F in_reply_to=<COMMENT_ID>
   ```
   Tone: collegial. Cite the ADR / `file:line` / commit SHA that backs the call,
   not "you're wrong." (Posting to Copilot's threads is an external write — if a
   permission gate blocks it, surface the intended reply to the user instead of
   working around it.)
3. **Defer.** Real concern, out of scope → reply with the deferral + reasoning,
   optionally file a follow-up issue and reference it.

Track every decision in a running list — step 9 needs it. Then push:
```bash
git push 2>&1 | tail -3
```

## Step 6 — Decide on a second review

Be honest, not optimistic. A needless second pass costs ~10 min of latency and one
churn round; the benefit is catching bugs the fixes introduced.

**Worth requesting** if any of:
- A fix added genuinely new logic (not a rename/comment/1-line tweak).
- The fixes touched a different surface than the first review covered.
- A fix changed render/state-resolution shape (e.g. `ResolveCell`, frame pooling)
  and a cheap second look is warranted.
- You deferred a first-pass concern and want a second opinion on the deferral.

**Skip** if all fixes were mechanical, all within the already-reviewed surface,
you pushed back on most comments, or the only open thread is a known acknowledged
gap. State the call explicitly ("a second pass is/isn't warranted because …").
If skipping, jump to step 9 and surface the skip in the report so the user can
override.

## Step 7 — Re-request review

Copilot does **not** auto-re-fire on later pushes. Request with the literal
`@copilot` form (`gh` 2.92.0+ has a special code path for it; this repo is on
2.94.0):
```bash
gh pr edit $PR_NUM --add-reviewer @copilot
```
The literal `@copilot` (with the `@`) is required — it emits a fresh
`review_requested` timeline event even when Copilot already reviewed the current
head. **Do not reach for** these — all verified to silently no-op here:
- `gh pr edit --add-reviewer Copilot` (no `@`) — resolves to "user not found" or
  silently dedups.
- REST `POST /requested_reviewers` with `reviewers[]=Copilot`.
- GraphQL `requestReviews` with `botIds:[…]` — returns an empty `reviewRequests`,
  no event (confirmed 2026-06-17 against the `copilot-swe-agent` bot id).

Verify the event fired:
```bash
gh api repos/mike-levenick/mythicloot/issues/$PR_NUM/timeline \
  --jq '.[] | select(.event=="review_requested") | "\(.created_at) -> \(.requested_reviewer.login // "?")"' | tail -3
```

## Step 8 — Wait for and address the second review

Reuse step 4's polling (filter `submitted_at` to the latest pass) and step 5's
address flow (same silent-on-fix policy). After this, **do not request a third
round** unless the second-pass fixes added substantial new logic of a different
kind, or the user asks. The diminishing-returns curve is steep.

## Step 9 — Final report

```
## Tweaks landed
- <substantive change from the Copilot iterations>

## Pushback
- <comment topic>: <one-line reasoning>   ← the most useful section; judgment calls to sanity-check

## Deferred
- <comment topic> → issue #N (or: noted, no issue filed)
```
Skip mechanical tweaks unless the user wants the full ledger.

## Step 10 — Flip to ready

```bash
gh pr ready $PR_NUM
```
This signals "ready for the user to merge." (CI already ran on the draft; flipping
doesn't change CI here — it's a human signal and unblocks the merge button, since
draft PRs can't be merged.)

## Step 11 — Stop

Tell the user the PR is ready, link `PR_URL`, and stop. **Do not poll CI** — that's
the user's job. They come back with "merge it" or "CI's red; help."

## Common pitfalls

- **Don't skip the in-game gate (step 2).** A syntax-clean addon can still render
  a broken UI, leak stale pooled-frame state, or error on a fresh character. The
  gate is the whole point.
- **Don't push to `main`.** Branch-protected, PR-only. Version bumps + releases go
  through the separate `release` skill, never this one.
- **Don't post "Fixed in `<SHA>`" replies.** Reply only to push back or defer.
- **Don't use `--add-reviewer Copilot` (no `@`), REST `requested_reviewers`, or
  GraphQL `botIds`** to request Copilot — only `--add-reviewer @copilot` works.
- **Don't run a third Copilot pass by reflex.** Trust the user to ask.
- **Don't read reference-addon source** to "resolve" a Copilot suggestion (ADR
  0001). API facts come from Blizzard / the wiki only.

## References

- `CONTEXT.md` — ubiquitous language; check feature changes against the glossary.
- `docs/adr/` — esp. 0001 (clean-room), 0002 (runtime data), 0007 (EJ cache),
  0008 (Voidforge claims).
- `.github/workflows/ci.yml` — the Lua 5.1 syntax check CI runs on every PR.
- `.claude/skills/release/SKILL.md` — the sibling release flow (chore bump PR →
  stamp → tag → publish). `/prep` ends at "ready"; releases are separate.
