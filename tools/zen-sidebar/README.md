# zen-sidebar

Keeps the Zen browser sidebar (spaces, essentials, folders, pinned tabs) in the
private dotfiles (`~/dotfiles-private/zen/sidebar.json`: the tabs are personal).

```bash
zen-sidebar export   # Zen profile -> sidebar.json (Zen can be open)
zen-sidebar show     # print the saved layout
zen-sidebar apply    # sidebar.json -> Zen profile (close Zen first)
```

- Zen's own files (`zen-sessions.jsonlz4`, the session store) are binary and
  rewritten all the time, so they can't be symlinked like other configs. This
  tool stores only the layout: names, URLs, icons and order.
- The repo is public, so `export` cleans personal URLs (a Gmail message, a
  Claude/Gemini chat, a Google Sheet…) to the site's root. The rules are
  `CLEAN_RULES` in `zen_sidebar.py`.
- `apply` rebuilds the pinned tabs and folders of each space in the file and
  keeps unpinned tabs. A pinned tab whose URL is already there is reused, so it
  keeps its history. The previous session files are copied to
  `<profile>/zen-sidebar-backup-<date>/` first.
- Options: `--profile DIR` (default: the default profile in
  `~/.config/zen/profiles.ini`), `--file FILE` (default:
  `$ZEN_SIDEBAR_FILE` or `~/dotfiles-private/zen/sidebar.json`).
- Export by hand after changing the sidebar, then commit.
