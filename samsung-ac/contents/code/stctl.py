#!/usr/bin/env python3
"""SmartThings helper for the Samsung AC plasmoid.

Every subcommand prints a single JSON object on stdout. On failure it prints
{"error": "...", "code": "..."} and exits with status 1.

  setup <client_id> <client_secret> <redirect_uri>   save credentials, print authorize URL
  auth-code <code | redirect URL | httpbin page>      exchange the code for tokens
  state                                               is the plasmoid authorized?
  devices                                             list air conditioners
  status <device_id>                                  flattened status of the main component
  cmd <device_id> <capability> <command> [args-json]  send a command
  raw <device_id>                                     raw status (for debugging)
  describe <device_id>                                commands of every capability (for debugging)
"""
import base64
import fcntl
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.smartthings.com/v1"
AUTHORIZE_URL = "https://api.smartthings.com/oauth/authorize"
TOKEN_URL = "https://auth-global.api.smartthings.com/oauth/token"
SCOPES = "r:devices:* x:devices:*"

CONF_DIR = os.path.join(
    os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"),
    "samsung-ac-plasmoid",
)
STORE = os.path.join(CONF_DIR, "auth.json")
LOCK = STORE + ".lock"


class Fail(Exception):
    def __init__(self, message, code="error"):
        super().__init__(message)
        self.code = code


# --- storage -----------------------------------------------------------------

def load():
    try:
        with open(STORE) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def save(store):
    os.makedirs(CONF_DIR, mode=0o700, exist_ok=True)
    tmp = STORE + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(store, f, indent=2)
    os.replace(tmp, STORE)


class locked:
    """Serialize token refreshes: refresh tokens are single use, so two
    concurrent refreshes would log the user out."""

    def __enter__(self):
        os.makedirs(CONF_DIR, mode=0o700, exist_ok=True)
        self.f = open(LOCK, "w")
        fcntl.flock(self.f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        fcntl.flock(self.f, fcntl.LOCK_UN)
        self.f.close()


# --- http --------------------------------------------------------------------

def http(method, url, data=None, headers=None, form=False):
    h = dict(headers or {})
    body = None
    if data is not None:
        if form:
            body = urllib.parse.urlencode(data).encode()
            h["Content-Type"] = "application/x-www-form-urlencoded"
        else:
            body = json.dumps(data).encode()
            h["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=h, method=method)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            raw = r.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:400]
        code = "unauthorized" if e.code == 401 else f"http_{e.code}"
        raise Fail(f"HTTP {e.code}: {detail}", code)
    except urllib.error.URLError as e:
        raise Fail(f"Falha de rede: {e.reason}", "network")
    return json.loads(raw) if raw else {}


def token_request(store, params):
    basic = base64.b64encode(f"{store['client_id']}:{store['client_secret']}".encode()).decode()
    params = dict(params, client_id=store["client_id"])
    try:
        t = http("POST", TOKEN_URL, params, {"Authorization": "Basic " + basic}, form=True)
    except Fail as e:
        if e.code in ("unauthorized", "http_400"):
            raise Fail(f"Autorização recusada pela SmartThings ({e}). Refaça a autorização.", "not_authorized")
        raise
    store["access_token"] = t["access_token"]
    store["refresh_token"] = t.get("refresh_token", store.get("refresh_token"))
    store["expires_at"] = time.time() + int(t.get("expires_in", 86400))
    save(store)


def access_token(force_refresh=False):
    with locked():
        store = load()
        if not store.get("refresh_token"):
            raise Fail("Widget ainda não autorizado na SmartThings.", "not_authorized")
        if force_refresh or store.get("expires_at", 0) - 300 < time.time():
            token_request(store, {"grant_type": "refresh_token", "refresh_token": store["refresh_token"]})
        return store["access_token"]


def api(method, path, data=None):
    for attempt in range(2):
        token = access_token(force_refresh=attempt > 0)
        try:
            return http(method, API + path, data, {"Authorization": "Bearer " + token})
        except Fail as e:
            if e.code != "unauthorized" or attempt > 0:
                raise


# --- commands ----------------------------------------------------------------

def cmd_setup(client_id, client_secret, redirect_uri):
    store = {"client_id": client_id.strip(), "client_secret": client_secret.strip(),
             "redirect_uri": redirect_uri.strip()}
    with locked():
        save(store)
    query = urllib.parse.urlencode({
        "client_id": store["client_id"],
        "response_type": "code",
        "redirect_uri": store["redirect_uri"],
        "scope": SCOPES,
    })
    return {"url": AUTHORIZE_URL + "?" + query}


def extract_code(text):
    text = text.strip()
    m = re.search(r"""\bcode["'=:\s]+["']?([A-Za-z0-9_\-]+)""", text)
    return m.group(1) if m else text


def cmd_auth_code(text):
    code = extract_code(text)
    with locked():
        store = load()
        if not store.get("client_id"):
            raise Fail("Rode o passo 1 (abrir autorização) antes.", "not_authorized")
        token_request(store, {"grant_type": "authorization_code", "code": code,
                              "redirect_uri": store["redirect_uri"]})
    return {"ok": True}


def cmd_state():
    store = load()
    return {"authorized": bool(store.get("refresh_token")),
            "client_id": store.get("client_id", ""),
            "redirect_uri": store.get("redirect_uri", "")}


def cmd_devices():
    items = api("GET", "/devices?capability=airConditionerMode").get("items", [])
    return {"devices": [{"deviceId": d["deviceId"],
                         "label": d.get("label") or d.get("name") or d["deviceId"]} for d in items]}


def cmd_status(device_id):
    main = api("GET", f"/devices/{device_id}/components/main/status")
    caps = {}
    units = {}
    for cap, attrs in main.items():
        caps[cap] = {}
        for attr, entry in attrs.items():
            caps[cap][attr] = entry.get("value") if isinstance(entry, dict) else entry
            if isinstance(entry, dict) and entry.get("unit"):
                units[f"{cap}.{attr}"] = entry["unit"]
    disabled = caps.get("custom.disabledCapabilities", {}).get("disabledCapabilities") or []
    return {"caps": caps, "units": units, "disabled": disabled, "ts": time.time()}


def cmd_send(device_id, capability, command, args_json="[]"):
    args = json.loads(args_json)
    body = {"commands": [{"component": "main", "capability": capability,
                          "command": command, "arguments": args}]}
    return api("POST", f"/devices/{device_id}/commands", body)


def cmd_raw(device_id):
    return api("GET", f"/devices/{device_id}/status")


def cmd_describe(device_id):
    device = api("GET", f"/devices/{device_id}")
    main = next((c for c in device.get("components", []) if c["id"] == "main"), {})
    out = {}
    for cap in main.get("capabilities", []):
        try:
            d = api("GET", f"/capabilities/{urllib.parse.quote(cap['id'])}/{cap.get('version', 1)}")
            out[cap["id"]] = {name: [a.get("name") for a in c.get("arguments", [])]
                              for name, c in d.get("commands", {}).items()}
        except Fail as e:
            out[cap["id"]] = {"error": str(e)}
    return out


COMMANDS = {
    "setup": cmd_setup,
    "auth-code": cmd_auth_code,
    "state": cmd_state,
    "devices": cmd_devices,
    "status": cmd_status,
    "cmd": cmd_send,
    "raw": cmd_raw,
    "describe": cmd_describe,
}


def main(argv):
    if len(argv) < 2 or argv[1] not in COMMANDS:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        result = COMMANDS[argv[1]](*argv[2:])
    except Fail as e:
        print(json.dumps({"error": str(e), "code": e.code}, ensure_ascii=False))
        return 1
    except TypeError as e:
        print(json.dumps({"error": f"Argumentos inválidos: {e}", "code": "usage"}, ensure_ascii=False))
        return 1
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
