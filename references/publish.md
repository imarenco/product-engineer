# Publishing evidence — `scripts/media.sh publish`

Used by `phases/ship.md` §3 and `phases/qa-report.md` §3.

Where PR media goes comes from `$CTX` § Git & PR. It runs only after the verdict gate (Ship §2) or
the user's share choice (QA report §3), so nothing leaves the machine before that. The default for
GitHub (no API for PR attachments) is an orphan assets branch `pr-assets/<TICKET>` in the same repo — only media, never merged; keep it
after merge, the PR's images point at its commit. Run it as one tool call (the `M=` line doesn't survive into another call), with literal paths. The
`setopt` line makes zsh (the Bash tool's shell) drop globs that match nothing, such as a missing
`forced/`; media.sh skips them too and fails only when nothing is left:
```
setopt nullglob 2>/dev/null
M=$SKILL/scripts/media.sh
$M jpg $W/shots/*/ac*.png $W/shots/*/forced/ac*.png          # half-size JPEGs, ~45–100 KB each
$M publish <TICKET> $W/shots/*/ac*.jpg $W/shots/*/forced/ac*.jpg $W/shots/*/workflow.mp4 \
  $W/shots/*/ac[0-9]*.mp4 $W/shots/*/forced/*.mp4
# each FAIL or waived AC (and every --test-only finding) adds its own failures, never every fail- shot
# (look-/unnamed debug steps fail too): $M jpg $W/shots/*/fail-ac<N>-*.png, then those fail-ac<N>-*.jpg
# in the publish list — the PR shows what fails, not only what passes
```
It commits through a temporary index (working tree and branch untouched), pushes, and prints
`<name> <url>` per file — a SHA-pinned `https://github.com/<owner>/<repo>/blob/<sha>/<file>?raw=true`,
always the last field; files under
`shots/` are named by their path below it with `/` → `-` (`shots/ios/ac1-1-x.jpg` → `ios-ac1-1-x.jpg`,
`shots/ios/forced/v.mp4` → `ios-forced-v.mp4`); two files mapping to one name stop the publish. Backend evidence is text:
paste `backend-evidence.md` into the PR body instead of publishing it — plus, for a FAIL or waived
backend AC, its `shots/backend/ac<N>-*.txt` transcripts (they aren't in the report: only passing
steps are saved flows). Save publish's output as `$W/media.md` for the PR body.
- In a private repo, images render inline for members only; videos are links (GitHub plays only
  drag-and-drop uploads inline). People without repo access can't open them — `$CTX` § People & process.
- Publish only shots of the finished app — never one showing data you wouldn't paste in the PR text.
- Nothing to publish (e.g. a pure-logic ticket) → say so in `media.md`.
