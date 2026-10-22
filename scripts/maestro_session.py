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
import fcntl, hashlib, json, os, queue, select, signal, socket, subprocess, sys, tempfile, threading, time

IDLE = 45 * 60
CALL_TIMEOUT = int(os.environ.get("MAESTRO_CALL_TIMEOUT", 600))  # seconds one maestro call may take
SOCK = os.path.join(tempfile.gettempdir(),
                    "maestro-%s.sock" % hashlib.sha1(os.environ.get("SIM_SESSION", os.getcwd()).encode()).hexdigest()[:10])


class ClientGone(Exception):
    """The client hung up mid-call (the agent's tool call timed out, a Ctrl-C)."""


def client_gone(conn):
    # the client sends nothing while it waits, so the socket only turns readable when it closes
    try:
        r, _, _ = select.select([conn], [], [], 0)
        return bool(r) and conn.recv(1, socket.MSG_PEEK) == b""
    except OSError:
        return True


class Mcp:
    def __init__(self):
        # own process group: maestro starts xcodebuild + the on-device driver as children, and a
        # restart that leaves them running gets two drivers fighting ("Device became unreachable")
        self.p = subprocess.Popen(["maestro", "mcp", "--no-viewer"], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
                                  start_new_session=True)
        self.n = 0
        # A reader thread, not select() on the pipe: readline() buffers ahead, so a log line and a
        # response written together would leave the response in the buffer with select() never firing.
        self.lines = queue.Queue()
        threading.Thread(target=self._read, daemon=True).start()
        try:
            self.call("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                                     "clientInfo": {"name": "product-engineer", "version": "1"}})
            self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        except Exception:
            self.kill()  # a maestro that failed its handshake would keep the device driver
            raise

    def kill(self):
        try:
            os.killpg(self.p.pid, signal.SIGTERM)
            self.p.wait(timeout=10)
        except Exception:
            try:
                os.killpg(self.p.pid, signal.SIGKILL)
            except Exception:
                pass

    def _read(self):
        for line in self.p.stdout:
            self.lines.put(line)
        self.lines.put(None)  # EOF: maestro exited

    def _send(self, o):
        self.p.stdin.write(json.dumps(o) + "\n")
        self.p.stdin.flush()

    def call(self, method, params, cancel=None):
        self.n += 1
        self._send({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params})
        end = time.time() + CALL_TIMEOUT
        while time.time() < end:
            # every turn, not only when maestro is quiet: a chatty maestro must not hide a gone client
            if cancel and cancel():
                raise ClientGone()
            try:
                line = self.lines.get(timeout=1)
            except queue.Empty:
                if self.p.poll() is not None:
                    raise RuntimeError("maestro mcp exited")
                if cancel and cancel():
                    raise ClientGone()
                continue
            if line is None:
                raise RuntimeError("maestro mcp exited")
            if line.lstrip().startswith("{"):
                try:
                    o = json.loads(line)
                except ValueError:
                    continue
                if o.get("id") == self.n:
                    return o
        raise TimeoutError("maestro call timed out")

    def tool(self, name, args, cancel=None):
        o = self.call("tools/call", {"name": name, "arguments": args}, cancel)
        if "error" in o:
            return False, json.dumps(o["error"])
        res = o.get("result", {})
        text = "\n".join(c.get("text", "") for c in res.get("content", []) if c.get("type") == "text")
        return not res.get("isError"), text


LOST = ("unreachable", "not ready", "session error", "Connection refused", "Internal error")


def handle(mcp, req, cancel=None):
    if req["op"] == "run":
        return mcp.tool("run", {"device_id": req["device"], "files": [req["flow"]]}, cancel)
    ok, text = mcp.tool("inspect_screen", {"device_id": req["device"]}, cancel)
    if req["op"] == "warm":  # any cheap call connects the device driver
        text = "session ready" if ok else text
    return ok, text


def serve():
    # one server per session: two first calls at once each start one, and the loser's cleanup would
    # delete the winner's socket. The lock lives as long as this process.
    lock = open(SOCK + ".lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return
    try:
        os.unlink(SOCK)
    except FileNotFoundError:
        pass
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCK)
    srv.listen(4)
    srv.settimeout(IDLE)
    mcp = None  # started by the first request, and again after a failure
    # whatever happens, never leave a socket file behind: the next client would connect to nothing
    try:
        while True:
            try:
                conn, _ = srv.accept()
            except socket.timeout:
                break
            with conn:
                try:
                    req = json.loads(conn.makefile().readline())
                    req["op"]
                except (ValueError, KeyError, TypeError, OSError):
                    continue  # a client that connected and left (or sent garbage): not fatal
                if req["op"] == "stop":
                    conn.sendall(b'{"ok": true, "text": "stopped"}\n')
                    break
                for attempt in range(2):
                    try:
                        if mcp is None:
                            try:
                                mcp = Mcp()
                            except Exception as e:
                                ok, text = False, "session error: %s%s" % ("reconnect failed: " if attempt else "", e)
                                break
                        ok, text = handle(mcp, req, lambda: client_gone(conn))
                    except ClientGone:
                        # nobody is waiting for this flow any more: stop it now, so the next call (or
                        # `stop`) isn't blocked behind it for up to CALL_TIMEOUT
                        mcp.kill()
                        mcp = None
                        ok, text = False, "client gone"
                        break
                    except TimeoutError:
                        # a hung maestro: never re-run the flow (the client would give up first) —
                        # restart it on the next request instead
                        mcp.kill()
                        mcp = None
                        ok, text = False, "maestro call timed out after %d s; the flow was not re-run" % CALL_TIMEOUT
                        break
                    except Exception as e:
                        ok, text = False, "session error: %s" % e
                    # another maestro process (a plain `maestro test`, a second session) took the device
                    # driver, or maestro died: reconnect once and retry. A failed reconnect is reported
                    # and retried on the next request, never fatal.
                    if ok or attempt or not any(k in text for k in LOST):
                        break
                    mcp.kill()
                    mcp = None
                try:
                    conn.sendall((json.dumps({"ok": ok, "text": text}) + "\n").encode())
                except OSError:
                    pass  # the client went away (Ctrl-C); the session stays up for the next call
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
    try:
        s.sendall((json.dumps(req) + "\n").encode())
        line = s.makefile().readline()
    except OSError as e:
        return {"ok": False, "text": "session error: no answer from the session server (%s); run the step again" % e}
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
