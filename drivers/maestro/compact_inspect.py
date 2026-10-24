"""Print a Maestro screen hierarchy as one line per element that a selector can use.

  python3 -I compact_inspect.py <inspect.json> [max-lines]
  python3 -I compact_inspect.py <inspect.json> --a11y      controls a screen reader can't name

Only elements with an id, text, accessibility label, hint or value are printed (layout containers
carry nothing to tap or assert on), as `id=<rid> "<text>" a11y="…" hint="…" value="…" <flags> [bounds]`.
Flags are listed only when they differ from the schema's defaults (e.g. `not-enabled`, `selected`).
The full JSON stays in the file; exit 1 only if it isn't JSON, so the driver can print it raw.
--a11y: elements with a test id (or Android `clickable`) and no text, accessibility label or hint in them
or anything inside them — VoiceOver / TalkBack has nothing to read. A container whose children carry
the labels isn't one. No such control on the screen → it says nothing was checked.
"""
import json, re, sys

sys.setrecursionlimit(20000)  # real hierarchies nest deep (a WebView's DOM)

try:
    o = json.load(open(sys.argv[1]))
except RecursionError:
    sys.exit("the hierarchy nests too deep to read: %s" % sys.argv[1])
except (OSError, ValueError):
    sys.exit(1)
A11Y = "--a11y" in sys.argv[2:]
cap = int(sys.argv[2]) if len(sys.argv) > 2 and not A11Y else 250
defaults = (o.get("ui_schema") or {}).get("defaults", {}) if isinstance(o, dict) else {}
rows = []


def walk(n):
    if isinstance(n, list):
        for x in n:
            walk(x)
        return
    if not isinstance(n, dict):
        return
    s = lambda *keys: str(next((n[k] for k in keys if n.get(k) not in (None, "")), ""))
    rid, txt, a11y = s("rid", "resource-id"), s("txt", "text"), s("a11y", "accessibilityText")
    hint, val = s("hint", "hintText"), s("val", "value")
    if rid or txt or a11y or hint or val:
        parts = ["id=" + rid] if rid else []
        if txt:
            parts.append(json.dumps(txt, ensure_ascii=False))
        if a11y and a11y != txt:
            parts.append("a11y=" + json.dumps(a11y, ensure_ascii=False))
        if hint:
            parts.append("hint=" + json.dumps(hint, ensure_ascii=False))
        if val:
            parts.append("value=" + json.dumps(val, ensure_ascii=False))
        for k in ("enabled", "focused", "selected", "checked"):
            if k in n and n[k] != defaults.get(k, n[k]):
                parts.append(k if n[k] else "not-" + k)
        parts.append(str(n.get("b") or n.get("bounds") or ""))
        rows.append(" ".join(p for p in parts if p))
    walk(n.get("c") or n.get("children") or [])


def unlabeled(n):
    # returns whether n or anything inside it is readable; collects the controls that aren't
    if isinstance(n, list):
        return any([unlabeled(x) for x in n])  # a list, not a generator: every child is visited
    if not isinstance(n, dict):
        return False
    inner = unlabeled(n.get("c") or n.get("children") or [])
    # a hint (placeholder) is read aloud by VoiceOver and TalkBack when there is no label
    readable = inner or any(spoken(n.get(k)) for k in ("txt", "text", "a11y", "accessibilityText", "hint", "hintText"))
    rid = str(n.get("rid") or n.get("resource-id") or "").strip()
    if rid or n.get("clickable") is True:
        checked.append(rid)
        if not readable:
            rows.append("unlabeled: %s %s" % ("id=" + rid if rid else "clickable", n.get("b") or n.get("bounds") or ""))
    return readable


def spoken(v):
    # an icon font's glyph (Private Use Area) is text on screen but nothing a screen reader can say
    if v is None or v is False or v == "":
        return False
    return bool(PUA.sub("", str(v)).strip())


# icon-font glyphs and zero-width characters read as nothing
PUA = re.compile("[\ue000-\uf8ff\U000f0000-\U0010ffff\u200b-\u200d\u2060\ufeff]")
checked = []


root = o.get("elements", o) if isinstance(o, dict) else o
if A11Y:
    try:
        unlabeled(root)
    except RecursionError:
        sys.exit("a11y: the hierarchy nests too deep to read: %s" % sys.argv[1])
    if not checked:
        print("a11y: no control with a test id (or clickable) on this screen — nothing checked (a WebView,"
              " a canvas, an error, or no test ids): HUMAN. Full hierarchy: %s" % sys.argv[1])
        sys.exit(0)
    print("\n".join(rows) if rows else "a11y: all %d controls on this screen have a text or label" % len(checked))
    if rows:
        print("a11y: %d control(s) with nothing for a screen reader to read — give each an accessibility label" % len(rows))
    sys.exit(0)
try:
    walk(root)
except RecursionError:
    sys.exit("the hierarchy nests too deep to read: %s" % sys.argv[1])
if not rows:
    # a WebView, canvas or spinner: nothing to select by — say so instead of dumping the whole tree
    print("no element with an id, text or label on this screen — full hierarchy: %s" % sys.argv[1])
    sys.exit(0)
print("\n".join(rows[:cap]))
if len(rows) > cap:
    print("… %d more elements: %s" % (len(rows) - cap, sys.argv[1]))
