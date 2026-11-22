#!/usr/bin/env python3
"""Save and restore the Zen browser sidebar (spaces, essentials, folders, pinned tabs).

    zen-sidebar export [--profile DIR] [--file FILE]   Zen profile -> sidebar.json
    zen-sidebar apply  [--profile DIR] [--file FILE]   sidebar.json -> Zen profile (Zen must be closed)
    zen-sidebar show   [--file FILE]                   print sidebar.json as a tree

FILE defaults to $ZEN_SIDEBAR_FILE or ~/dotfiles/config/zen/sidebar.json.
DIR defaults to the Default=1 profile in ~/.config/zen/profiles.ini.

Only the sidebar layout is stored (names, URLs, icons, order), never the browsing
session. Personal URLs (mail, chats, documents) are cleaned to the site's root
on export, because the dotfiles repo is public: see clean_url().
"""
import argparse, configparser, json, os, random, re, shutil, subprocess, sys, time, uuid
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

import lz4.block

ZEN_DIR = os.path.expanduser("~/.config/zen")
DEFAULT_FILE = os.environ.get("ZEN_SIDEBAR_FILE") or os.path.join(
    os.environ.get("ZEN_SIDEBAR_DOTFILES", os.path.expanduser("~/dotfiles")), "config/zen/sidebar.json")
# Files holding the session; zen-sessions.jsonlz4 is Zen's own store, the others
# are Firefox's window session (both are restored on startup, so both are edited).
SESSION_FILES = ["zen-sessions.jsonlz4", "sessionstore.jsonlz4",
                 "sessionstore-backups/recovery.jsonlz4", "sessionstore-backups/recovery.baklz4"]


# ------------------------------------------------------------------ mozlz4 files
def load(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"mozLz40\0":
        sys.exit(f"{path}: not a mozlz4 file")
    return json.loads(lz4.block.decompress(data[8:]))


def save(path, obj):
    raw = json.dumps(obj, separators=(",", ":"), ensure_ascii=False).encode()
    tmp = path + ".zen-sidebar.tmp"
    with open(tmp, "wb") as f:
        f.write(b"mozLz40\0" + lz4.block.compress(raw))
    os.replace(tmp, path)


# ------------------------------------------------------------------ helpers
def default_profile():
    ini = configparser.ConfigParser()
    ini.optionxform = str
    if not ini.read(os.path.join(ZEN_DIR, "profiles.ini")):
        sys.exit(f"No {ZEN_DIR}/profiles.ini: start Zen once first.")
    profiles = [s for s in ini.sections() if s.startswith("Profile")]
    chosen = next((s for s in profiles if ini[s].get("Default") == "1"), profiles[0] if profiles else None)
    if not chosen:
        sys.exit("No profile in profiles.ini")
    p = ini[chosen]["Path"]
    return p if ini[chosen].get("IsRelative", "1") == "0" else os.path.join(ZEN_DIR, p)


def zen_running():
    # Matches .../bin/zen, zen-beta, zen-bin, zen-twilight, but not this tool (zen-sidebar)
    return subprocess.run(["pgrep", "-f", r"bin/\.?zen(-beta|-bin|-twilight|-browser)?(-wrapped)?( |$)"],
                          capture_output=True).returncode == 0


def zen_id():
    """Zen's id style: '<ms timestamp>-<n>'."""
    return f"{int(time.time() * 1000)}-{random.randint(0, 99)}"


def entry(tab):
    """Current history entry of a session tab."""
    entries = tab.get("entries") or [{}]
    return entries[max(0, min(len(entries), tab.get("index", len(entries))) - 1)]


# Personal URLs -> generic ones (repo is public). (regex on host+path, replacement url, title)
CLEAN_RULES = [
    (r"^mail\.google\.com/", "https://mail.google.com/mail/u/0/#inbox", "Gmail"),
    (r"^(outlook\.(live|office|office365)\.com|outlook\.cloud\.microsoft)/", "https://outlook.cloud.microsoft/mail/", "Outlook"),
    (r"^gemini\.google\.com/", "https://gemini.google.com/app", "Gemini"),
    (r"^claude\.ai/", "https://claude.ai/new", "Claude"),
    (r"^chatgpt\.com/", "https://chatgpt.com/", "ChatGPT"),
    (r"^chat\.mistral\.ai/", "https://chat.mistral.ai/", None),
    (r"^docs\.google\.com/spreadsheets/", "https://docs.google.com/spreadsheets/", "Google Sheets"),
    (r"^docs\.google\.com/document/", "https://docs.google.com/document/", "Google Docs"),
    (r"^docs\.google\.com/presentation/", "https://docs.google.com/presentation/", "Google Slides"),
    (r"^drive\.google\.com/", "https://drive.google.com/", "Google Drive"),
    (r"^calendar\.google\.com/", "https://calendar.google.com/calendar/u/0/r", "Google Agenda"),
    (r"^onedrive\.live\.com/", "https://onedrive.live.com/", "OneDrive"),
]
DROP_PARAMS = {"list", "index", "start_radio", "pp", "si", "fbclid", "gclid", "flowName", "service",
               "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content"}
EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")


def clean_url(url, title):
    parts = urlsplit(url)
    hostpath = parts.netloc + parts.path
    for pattern, new_url, new_title in CLEAN_RULES:
        if re.search(pattern, hostpath):
            return new_url, new_title or title
    query = urlencode([(k, v) for k, v in parse_qsl(parts.query, keep_blank_values=True) if k not in DROP_PARAMS])
    title = EMAIL.sub("", title or "")
    title = re.sub(r"^\(\d+\)\s*", "", title).strip(" -–—|") or parts.netloc  # "(40) Video" unread counters
    return urlunsplit((parts.scheme, parts.netloc, parts.path, query, parts.fragment)), title


# ------------------------------------------------------------------ export
def export(profile, out):
    data = load(os.path.join(profile, "zen-sessions.jsonlz4"))
    folders = {f["id"]: f for f in data.get("folders", [])}
    result = {"version": 1, "spaces": []}
    for space in data.get("spaces", []):
        ws = space["uuid"]
        tabs = [t for t in data["tabs"] if t.get("pinned") and t.get("zenWorkspace") == ws and not t.get("zenIsEmpty")]

        def item(t):
            e = entry(t)
            url, title = clean_url(e.get("url", ""), e.get("title", ""))
            it = {"title": title, "url": url}
            if t.get("zenPinnedIcon"):
                it["icon"] = t["zenPinnedIcon"]
            return it

        essentials = [item(t) for t in tabs if t.get("zenEssential")]
        items, seen_folders = [], set()
        for t in tabs:
            if t.get("zenEssential"):
                continue
            gid = t.get("groupId")
            if gid and gid in folders:
                if gid not in seen_folders:
                    seen_folders.add(gid)
                    f = folders[gid]
                    entry_ = {"folder": f["name"], "tabs": []}
                    if f.get("collapsed"):
                        entry_["collapsed"] = True
                    if f.get("userIcon"):
                        entry_["icon"] = f["userIcon"]
                    items.append(entry_)
                next(i for i in items if i.get("folder") == folders[gid]["name"])["tabs"].append(item(t))
            else:
                items.append(item(t))
        # Empty folders still belong to the layout
        for gid, f in folders.items():
            if f.get("workspaceId") == ws and gid not in seen_folders:
                items.append({"folder": f["name"], "tabs": []})
        sp = {"name": space.get("name", "Space"), "essentials": essentials, "pinned": items}
        if space.get("icon"):
            sp["icon"] = space["icon"]
        if space.get("theme"):
            sp["theme"] = space["theme"]
        result["spaces"].append(sp)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"Exported {sum(len(s['essentials']) + len(s['pinned']) for s in result['spaces'])} sidebar items "
          f"from {len(result['spaces'])} space(s) to {out}")


# ------------------------------------------------------------------ apply
def new_tab(url, title, ws, essential=False, group=None, icon=None, empty=False):
    return {
        "entries": [{"url": url, "title": title or url, "triggeringPrincipal_base64": '{"3":{}}'}],
        "lastAccessed": int(time.time() * 1000), "pinned": True, "hidden": False,
        **({"groupId": group} if group else {}),
        "zenWorkspace": ws, "zenSyncId": zen_id(), "zenEssential": essential,
        "zenDefaultUserContextId": None, "zenPinnedIcon": icon, "zenIsEmpty": empty,
        "zenHasStaticIcon": bool(icon), "zenGlanceId": None, "zenIsGlance": False,
        "_zenPinnedInitialState": {"entry": {"url": url, "title": title}, "image": None},
        "zenLiveFolderItemId": None, "searchMode": None, "userContextId": 0,
        "attributes": {}, "index": 1, "userTypedValue": "", "userTypedClear": 0,
    }


def build(session, layout):
    """Rebuild pinned tabs/folders of every space named in layout. Unpinned tabs are kept.
    Existing pinned tabs whose URL (cleaned) matches are reused, so they keep their state."""
    spaces = session.setdefault("spaces", [])
    old_pinned = [t for t in session.get("tabs", []) if t.get("pinned")]
    unpinned = [t for t in session.get("tabs", []) if not t.get("pinned")]
    folders = [f for f in session.get("folders", [])]
    groups = [g for g in session.get("groups", [])]
    pool = {}  # (ws, cleaned url) -> existing tabs
    for t in old_pinned:
        if not t.get("zenIsEmpty"):
            e = entry(t)
            pool.setdefault((t.get("zenWorkspace"), clean_url(e.get("url", ""), "")[0]), []).append(t)

    pinned_out = []
    for sp in layout["spaces"]:
        space = next((s for s in spaces if s.get("name") == sp["name"]), None)
        if not space:
            space = {"uuid": "{%s}" % uuid.uuid4(), "name": sp["name"], "containerTabId": 0,
                     "hasCollapsedPinnedTabs": False,
                     "theme": {"type": "gradient", "gradientColors": [], "opacity": 0.5, "texture": 0}}
            spaces.append(space)
        if sp.get("theme"):
            space["theme"] = sp["theme"]
        if sp.get("icon"):
            space["icon"] = sp["icon"]
        ws = space["uuid"]
        old_ws_folders = {f["name"]: f for f in folders if f.get("workspaceId") == ws}
        folders = [f for f in folders if f.get("workspaceId") != ws]
        old_ids = {f["id"] for f in old_ws_folders.values()}
        groups = [g for g in groups if g.get("id") not in old_ids]

        def take(it, essential=False, group=None):
            reuse = pool.get((ws, clean_url(it["url"], "")[0]))
            if reuse:
                t = reuse.pop(0)
                t["zenEssential"] = essential
                t.pop("groupId", None)
                if group:
                    t["groupId"] = group
                if it.get("icon"):
                    t["zenPinnedIcon"] = it["icon"]
                return t
            return new_tab(it["url"], it.get("title"), ws, essential, group, it.get("icon"))

        for it in sp.get("essentials", []):
            pinned_out.append(take(it, essential=True))
        prev = None
        for it in sp.get("pinned", []):
            if "folder" not in it:
                t = take(it)
                pinned_out.append(t)
                prev = {"type": "tab", "id": t["zenSyncId"]}
                continue
            old = old_ws_folders.get(it["folder"])
            fid = old["id"] if old else zen_id()
            empty = new_tab("about:blank", None, ws, group=fid, empty=True)
            folders.append({"pinned": True, "splitViewGroup": False, "id": fid, "name": it["folder"],
                            "collapsed": bool(it.get("collapsed")), "saveOnWindowClose": True, "parentId": None,
                            "prevSiblingInfo": prev, "emptyTabIds": [empty["zenSyncId"]],
                            "userIcon": it.get("icon", ""), "workspaceId": ws})
            groups.append({"pinned": True, "splitView": False, "id": fid, "name": it["folder"],
                           "color": "zen-workspace-color", "collapsed": bool(it.get("collapsed")),
                           "saveOnWindowClose": True})
            prev = {"type": "group", "id": fid}
            pinned_out.append(empty)
            for t in it.get("tabs", []):
                pinned_out.append(take(t, group=fid))

    handled = {s["uuid"] for s in spaces if s.get("name") in {sp["name"] for sp in layout["spaces"]}}
    kept_other = [t for t in old_pinned if t.get("zenWorkspace") not in handled]
    session["tabs"] = kept_other + pinned_out + unpinned
    session["folders"] = folders
    session["groups"] = groups
    return len(pinned_out)


def apply(profile, src):
    if zen_running():
        sys.exit("Zen is running: close it completely, then run apply again.")
    with open(src) as f:
        layout = json.load(f)
    backup = os.path.join(profile, f"zen-sidebar-backup-{time.strftime('%Y%m%d-%H%M%S')}")
    os.makedirs(backup)
    count = None
    for rel in SESSION_FILES:
        path = os.path.join(profile, rel)
        if not os.path.exists(path):
            continue
        os.makedirs(os.path.dirname(os.path.join(backup, rel)), exist_ok=True)
        shutil.copy2(path, os.path.join(backup, rel))
        data = load(path)
        if rel == "zen-sessions.jsonlz4":
            count = build(data, layout)
        else:
            for w in data.get("windows", []):
                sel = w.get("selected", 1)
                selected_tab = w["tabs"][sel - 1] if 0 < sel <= len(w["tabs"]) else None
                n = build(w, layout)
                w["selected"] = (w["tabs"].index(selected_tab) + 1) if selected_tab in w["tabs"] else n + 1
                w["selected"] = max(1, min(w["selected"], len(w["tabs"])))
        save(path, data)
    if count is None:
        sys.exit(f"No zen-sessions.jsonlz4 in {profile}: start Zen once first.")
    print(f"Applied {count} pinned tabs (incl. folders' hidden placeholders) to {profile}")
    print(f"Previous session files saved in {backup}")


# ------------------------------------------------------------------ show
def show(src):
    with open(src) as f:
        layout = json.load(f)
    for sp in layout["spaces"]:
        print(f"[{sp['name']}]")
        for it in sp.get("essentials", []):
            print(f"  ★ {it['title']}  {it['url']}")
        for it in sp.get("pinned", []):
            if "folder" in it:
                print(f"  📁 {it['folder']}")
                for t in it["tabs"]:
                    print(f"      {t['title']}  {t['url']}")
            else:
                print(f"  {it['title']}  {it['url']}")


def main():
    ap = argparse.ArgumentParser(prog="zen-sidebar", description=__doc__.split("\n")[0])
    ap.add_argument("command", choices=["export", "apply", "show"])
    ap.add_argument("--profile", help="Zen profile directory (default: Default=1 in profiles.ini)")
    ap.add_argument("--file", default=DEFAULT_FILE, help=f"layout file (default: {DEFAULT_FILE})")
    a = ap.parse_args()
    if a.command == "show":
        return show(a.file)
    profile = a.profile or default_profile()
    (export if a.command == "export" else apply)(profile, a.file)


if __name__ == "__main__":
    main()
