"""Print a Maestro screen hierarchy as one line per element that a selector can use.

  python3 -I compact_inspect.py <inspect.json> [max-lines]

Only elements with an id, text, accessibility label, hint or value are printed (layout containers
carry nothing to tap or assert on), as `id=<rid> "<text>" a11y="…" hint="…" value="…" <flags> [bounds]`.
Flags are listed only when they differ from the schema's defaults (e.g. `not-enabled`, `selected`).
The full JSON stays in the file; exit 1 only if it isn't JSON, so the driver can print it raw.
"""
import json, sys

try:
    o = json.load(open(sys.argv[1]))
except (OSError, ValueError):
    sys.exit(1)
cap = int(sys.argv[2]) if len(sys.argv) > 2 else 250
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


walk(o.get("elements", o) if isinstance(o, dict) else o)
if not rows:
    # a WebView, canvas or spinner: nothing to select by — say so instead of dumping the whole tree
    print("no element with an id, text or label on this screen — full hierarchy: %s" % sys.argv[1])
    sys.exit(0)
print("\n".join(rows[:cap]))
if len(rows) > cap:
    print("… %d more elements: %s" % (len(rows) - cap, sys.argv[1]))
