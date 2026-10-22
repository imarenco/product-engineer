#!/usr/bin/env bash
# Evidence media shared by every test surface (mobile, web, backend).
# Usage: media.sh <join|frame|compare|jpg|mp4|publish> [...]
#   join <out.mp4> <clip.mp4>...      one video from clips (AVFoundation, fits 1920x1080; no ffmpeg needed)
#   frame <video> [seconds]           frame-<video>.png beside it, to check a recording isn't blank
#   compare <design.png> <shot.png> [out.png]  design | app side by side (default <shot>-vs-design.png)
#   jpg <png>...                      half-size JPEGs for the PR
#   mp4 <in.webm> <out.mp4>           convert a browser recording (ffmpeg, or ffmpeg-static from npm)
#   publish <KEY> <file>...           orphan branch pr-assets/<KEY>; prints `<name> <SHA-pinned URL>` per file (name = path after shots/)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"

ffmpeg_bin() {
  command -v ffmpeg && return
  local d="$HOME/.cache/product-engineer/web"
  [ -x "$d/node_modules/ffmpeg-static/ffmpeg" ] || (mkdir -p "$d" && cd "$d" && npm init -y >/dev/null \
    && npm i -s ffmpeg-static@5.3.0 >/dev/null 2>&1)
  echo "$d/node_modules/ffmpeg-static/ffmpeg"
}

case "${1:-}" in
  join)
    out="$2"; shift 2
    [ $# -gt 0 ] || { echo "join: no clips"; exit 1; }
    swift "$HERE/join.swift" "$out" "$@"
    ;;
  frame)
    swift "$HERE/frame.swift" "$2" "${3:-5}" "$(dirname "$2")/frame-$(basename "${2%.*}").png"
    ;;
  compare)
    swift "$HERE/compare.swift" "$2" "$3" "${4:-${3%.png}-vs-design.png}"
    ;;
  jpg)
    # a 1170x2532 PNG is 0.2-3 MB; the JPEG ~45-100 KB. A pattern that matched nothing is skipped.
    shift; for f in "$@"; do
      [ -f "$f" ] || { echo "jpg: skipped (no such file): $f" >&2; continue; }
      sips -s format jpeg -s formatOptions 70 -Z 1266 "$f" --out "${f%.png}.jpg" >/dev/null && echo "${f%.png}.jpg"
    done
    ;;
  mp4)
    "$(ffmpeg_bin)" -loglevel error -y -i "$2" -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$3" && echo "$3"
    ;;
  publish)
    # Commits through a private index (working tree and current branch untouched) and pushes.
    # Each file is named by its path after shots/ with / -> - (shots/ios/forced/x.mp4 -> ios-forced-x.mp4),
    # so every surface fits one branch. Every git step is checked: a failed step must never push.
    KEY="$2"; shift 2
    files=(); names=()
    for f in "$@"; do
      # a glob that matched nothing (no forced/ dir, a backend-only run) arrives literally: skip it, loudly
      [ -f "$f" ] || { echo "publish: skipped (no such file): $f" >&2; continue; }
      abs="$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
      case "$abs" in */shots/*) n="${abs##*/shots/}"; n="${n//\//-}" ;; *) n="$(basename "$abs")" ;; esac
      for x in ${names[@]+"${names[@]}"}; do [ "$x" = "$n" ] && { echo "publish: two files would publish as $n"; exit 1; }; done
      files+=("$abs"); names+=("$n")
    done
    [ ${#files[@]} -gt 0 ] || { echo "publish: no files to publish"; exit 1; }
    cd "$REPO" || exit 1
    NWO=$(gh repo view --json nameWithOwner -q .nameWithOwner) && [ -n "$NWO" ] || { echo "publish: gh repo view failed"; exit 1; }
    REF="refs/heads/pr-assets/$KEY"
    PARENT=$(git ls-remote origin "$REF" | cut -f1) || { echo "publish: git ls-remote failed"; exit 1; }
    if [ -n "$PARENT" ]; then git fetch -q origin "$REF" || { echo "publish: fetch of $REF failed"; exit 1; }; fi
    export GIT_INDEX_FILE; GIT_INDEX_FILE=$(mktemp -u); trap 'rm -f "$GIT_INDEX_FILE"' EXIT
    if [ -n "$PARENT" ]; then git read-tree "$PARENT" || exit 1; fi
    i=0
    while [ $i -lt ${#files[@]} ]; do
      blob=$(git hash-object -w "${files[$i]}") && [ -n "$blob" ] || { echo "publish: hash-object failed: ${files[$i]}"; exit 1; }
      git update-index --add --cacheinfo "100644,$blob,${names[$i]}" || exit 1
      i=$((i + 1))
    done
    TREE=$(git write-tree) && [ -n "$TREE" ] || { echo "publish: write-tree failed"; exit 1; }
    # the same files again (a re-run of publish) → reuse the existing commit: no empty commit, same URLs
    if [ -n "$PARENT" ] && [ "$TREE" = "$(git rev-parse "$PARENT^{tree}" 2>/dev/null)" ]; then COMMIT="$PARENT"
    else
      COMMIT=$(git commit-tree "$TREE" ${PARENT:+-p "$PARENT"} -m "chore: $KEY PR evidence") && [ -n "$COMMIT" ] \
        || { echo "publish: commit-tree failed, nothing pushed"; exit 1; }
    fi
    git push -q origin "$COMMIT:$REF" || { echo "publish: push failed"; exit 1; }
    # percent-encoded: a space, #, ? or % in a name would otherwise break or redirect the link
    # `<published name> <url>` per line — the format $W/media.md takes as is
    for n in "${names[@]}"; do echo "$n https://github.com/$NWO/blob/$COMMIT/$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$n")?raw=true"; done
    ;;
  *) sed -n '2,9p' "$0"; exit 2 ;;
esac
