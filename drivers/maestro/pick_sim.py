"""Pick the iOS simulator for a run. Prints `<udid>\t<source>\t<name>\t<iOS version>`; exit 1 = none.

  python3 -I pick_sim.py <device name or ""> <iOS version or ""> <app id or ""> [boot]

By name (IOS_DEVICE, the same on every machine): the matching available device, a booted one first,
then the newest iOS (or the IOS_RUNTIME version). No name — the fallback: a booted simulator, one with
the app installed first; with `boot`, when none is booted, the newest available iPhone.
"""
import json, subprocess, sys


def version(runtime):
    # com.apple.CoreSimulator.SimRuntime.iOS-26-1 -> "26.1"
    return runtime.rsplit("iOS-", 1)[-1].replace("-", ".")


def vkey(v):
    return [int(p) for p in v.split(".") if p.isdigit()]


def installed(udid, app):
    return bool(app) and subprocess.run(["xcrun", "simctl", "get_app_container", udid, app],
                                        capture_output=True).returncode == 0


def main(name, want, app, boot):
    out = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                         capture_output=True, text=True)
    if out.returncode:
        sys.exit("pick_sim: `xcrun simctl list` failed — is Xcode installed?")
    devs = [(d, version(rt)) for rt, ds in json.loads(out.stdout)["devices"].items()
            if ".iOS-" in rt for d in ds]
    if name:
        m = [(d, v) for d, v in devs if d["name"] == name
             and (not want or v == want or v.startswith(want + "."))]
        if not m:
            names = sorted({"%s (iOS %s)" % (d["name"], v) for d, v in devs if d["name"].startswith("iPhone")})
            sys.exit("pick_sim: no available simulator named %r%s — iPhones here: %s"
                     % (name, " on iOS " + want if want else "", ", ".join(names)))
        m.sort(key=lambda x: (x[0]["state"] == "Booted", vkey(x[1])), reverse=True)
        d, v = m[0]
        return d["udid"], "IOS_DEVICE", d["name"], v
    booted = [(d, v) for d, v in devs if d["state"] == "Booted"]
    booted.sort(key=lambda x: (installed(x[0]["udid"], app), vkey(x[1])), reverse=True)
    if booted:
        d, v = booted[0]
        return d["udid"], "fallback: booted", d["name"], v
    if boot:
        phones = [(d, v) for d, v in devs if d["name"].startswith("iPhone")]
        if phones:
            phones.sort(key=lambda x: vkey(x[1]), reverse=True)
            d, v = phones[0]
            return d["udid"], "fallback: newest iPhone", d["name"], v
    sys.exit("pick_sim: no simulator booted and none configured — set IOS_DEVICE in the project "
             "context, or run `boot`")


if __name__ == "__main__":
    a = sys.argv[1:] + ["", "", ""]
    print("\t".join(main(a[0], a[1], a[2], len(sys.argv) > 4 and sys.argv[4] == "boot")))
