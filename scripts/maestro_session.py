#!/usr/bin/env python3
"""One long-lived Maestro session for the mobile drivers (drivers/maestro/core.sh).

`maestro test` starts Java and the device driver on every call (~30 s). `maestro mcp` keeps them
up: the first command connects (~20 s), later ones take ~1 s. This wraps it behind a local Unix
socket so each mobile driver call (a fresh shell) reuses the same session.

  maestro_session.py run <device> <flow.yaml>   run a flow; prints the result; exit 0 = passed
  maestro_session.py inspect <device>           compact view hierarchy (JSON)
  maestro_session.py warm <device>              start + connect now (before recording)
  maestro_session.py stop                       end the session
The server starts on first use and exits after IDLE seconds without requests.
"""
import hashlib, json, os, select, signal, socket, subprocess, sys, tempfile, time

IDLE = 45 * 60
CALL_TIMEOUT = 600
SOCK = os.path.join(tempfile.gettempdir(),
                    "maestro-%s.sock" % hashlib.sha1(os.environ.get("SIM_SESSION", os.getcwd()).encode()).hexdigest()[:10])


class Mcp:
    def __init__(self):
        # own process group: maestro starts xcodebuild + the on-device driver as children, and a
        # restart that leaves them running gets two drivers fighting ("Device became unreachable")
        self.p = subprocess.Popen(["maestro", "mcp", "--no-viewer"], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
                                  start_new_session=True)
        self.n = 0
        self.call("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                                 "clientInfo": {"name": "product-engineer", "version": "1"}})
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def kill(self):
        try:
            os.killpg(self.p.pid, signal.SIGTERM)
            self.p.wait(timeout=10)
        except Exception:
            try:
                os.killpg(self.p.pid, signal.SIGKILL)
            except Exception:
                pass

    def _send(self, o):
        self.p.stdin.write(json.dumps(o) + "\n")
        self.p.stdin.flush()

    def call(self, method, params):
        self.n += 1
        self._send({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params})
        end = time.time() + CALL_TIMEOUT
        while time.time() < end:
            if self.p.poll() is not None:
                raise RuntimeError("maestro mcp exited")
            r, _, _ = select.select([self.p.stdout], [], [], 1)
            if r:
                line = self.p.stdout.readline()
                if line.lstrip().startswith("{"):
                    o = json.loads(line)
                    if o.get("id") == self.n:
                        return o
        raise TimeoutError("maestro call timed out")

    def tool(self, name, args):
        o = self.call("tools/call", {"name": name, "arguments": args})
        if "error" in o:
            return False, json.dumps(o["error"])
        res = o.get("result", {})
        text = "\n".join(c.get("text", "") for c in res.get("content", []) if c.get("type") == "text")
        return not res.get("isError"), text


LOST = ("unreachable", "not ready", "session error", "Connection refused", "Internal error")


def handle(mcp, req):
    if req["op"] == "run":
        return mcp.tool("run", {"device_id": req["device"], "files": [req["flow"]]})
    ok, text = mcp.tool("inspect_screen", {"device_id": req["device"]})
    if req["op"] == "warm":  # any cheap call connects the device driver
        text = "session ready" if ok else text
    return ok, text


def serve():
    try:
        os.unlink(SOCK)
    except FileNotFoundError:
        pass
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCK)
    srv.listen(4)
    srv.settimeout(IDLE)
    mcp = None
    # whatever happens, never leave a socket file behind: the next client would connect to nothing
    try:
        mcp = Mcp()
        while True:
            try:
                conn, _ = srv.accept()
            except socket.timeout:
                break
            with conn:
                req = json.loads(conn.makefile().readline())
                if req["op"] == "stop":
                    conn.sendall(b'{"ok": true, "text": "stopped"}\n')
                    break
                for attempt in range(2):
                    try:
                        ok, text = handle(mcp, req)
                    except Exception as e:
                        ok, text = False, "session error: %s" % e
                    # another maestro process (a plain `maestro test`, a second session) took the device
                    # driver, or maestro died: reconnect once and retry. A failed reconnect is reported
                    # and retried on the next request, never fatal.
                    if ok or attempt or not any(k in text for k in LOST):
                        break
                    mcp.kill()
                    try:
                        mcp = Mcp()
                    except Exception as e:
                        ok, text = False, "session error: reconnect failed: %s" % e
                        break
                conn.sendall((json.dumps({"ok": ok, "text": text}) + "\n").encode())
    finally:
        if mcp:
            mcp.kill()
        try:
            os.unlink(SOCK)
        except FileNotFoundError:
            pass


def connect():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(SOCK)
    return s


def request(req):
    try:
        s = connect()
    except OSError:
        if req["op"] == "stop":
            return {"ok": True, "text": "no session"}
        subprocess.Popen([sys.executable, __file__, "serve"], start_new_session=True,
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # wait for a real connection, not for the file: a stale socket file exists before the new
        # server has replaced it
        for _ in range(150):
            time.sleep(0.2)
            try:
                s = connect()
                break
            except OSError:
                pass
        else:
            return {"ok": False, "text": "session error: the session server didn't start (is `maestro` on PATH?)"}
    s.settimeout(CALL_TIMEOUT + 30)
    s.sendall((json.dumps(req) + "\n").encode())
    line = s.makefile().readline()
    if not line:
        return {"ok": False, "text": "session error: the session server stopped during the call; run the step again"}
    return json.loads(line)


def summary(text):
    """One line per flow, in the words `maestro test` used: COMPLETED / FAILED: <reason>."""
    try:
        o = json.loads(text)
    except ValueError:
        return text
    lines = ["COMPLETED (%s commands)" % o.get("total_commands_executed", "?") if r.get("success")
             else "FAILED: %s" % (r.get("error") or r.get("message")) for r in o.get("results", [])]
    return "\n".join(lines) or text


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    op = argv[0]
    if op == "serve":
        serve()
        return 0
    if op not in ("run", "inspect", "warm", "stop") or (op == "run" and len(argv) < 3) \
            or (op in ("inspect", "warm") and len(argv) < 2):
        print(__doc__)
        return 2
    req = {"op": op}
    if op in ("run", "inspect", "warm"):
        req["device"] = argv[1]
    if op == "run":
        req["flow"] = os.path.abspath(argv[2])
    res = request(req)
    print(summary(res["text"]) if op == "run" else res["text"])
    return 0 if res["ok"] else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
