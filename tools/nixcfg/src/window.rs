//! nixcfg's window and session.
//!
//! nixcfg runs in its own tmux server, so closing its window only detaches it:
//! an update or rebuild keeps going, and launching nixcfg again reattaches.
//! Under Hyprland its kitty window lives on the special workspace
//! "special:nixcfg" (a window rule in config/caelestia/hypr-user.lua), so it
//! is hidden and shown again instead of being closed and reopened: SUPER + I
//! or the tray icon show it, SUPER + I or Escape hide it.

use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};

pub const TMUX_SOCKET: &str = "nixcfg";
/// The kitty window class, matched by the Hyprland rules and SUPER + I.
pub const WINDOW_CLASS: &str = "nixcfg";
const SPECIAL: &str = "special:nixcfg";

/// tmux options: invisible (no status bar, no prefix key, no delay on
/// Escape), true colors, and the mouse and focus events passed through.
const TMUX_OPTIONS: &[&[&str]] = &[
    &["set", "-g", "status", "off"],
    &["set", "-g", "prefix", "None"],
    &["set", "-g", "prefix2", "None"],
    &["set", "-s", "escape-time", "0"],
    &["set", "-g", "default-terminal", "tmux-256color"],
    &["set", "-s", "terminal-features[99]", "*:RGB"],
    &["set", "-g", "focus-events", "on"],
];

pub fn in_session() -> bool {
    std::env::var_os("NIXCFG_SESSION").is_some()
}

/// Run nixcfg in its tmux session, or reattach to it if it is running.
///
/// Does nothing when already inside it, without tmux, or with --foreground
/// (which it removes from `args`).
pub fn attach_or_start(args: &mut Vec<String>) {
    if let Some(i) = args.iter().position(|a| a == "--foreground") {
        args.remove(i);
        return;
    }
    if in_session() || crate::cfg::which("tmux").is_none() {
        return;
    }
    let exe = std::env::current_exe().map(|p| p.to_string_lossy().into_owned()).unwrap_or_else(|_| "nixcfg".into());
    let mut cmd = Command::new("tmux");
    cmd.args(["-L", TMUX_SOCKET, "-f", "/dev/null"]);
    for option in TMUX_OPTIONS {
        cmd.args(*option).arg(";");
    }
    // -A attaches to the session when it already exists.
    cmd.args(["new-session", "-A", "-s", "nixcfg", "-e", "NIXCFG_SESSION=1", &exe]).args(&*args);
    let err = cmd.exec();
    eprintln!("nixcfg: could not start tmux: {err}");
}

fn in_hyprland() -> bool {
    std::env::var_os("HYPRLAND_INSTANCE_SIGNATURE").is_some()
}

/// Run Lua in Hyprland's config (its dispatchers are Lua functions).
fn hypr_lua(code: &str) {
    let _ = Command::new("hyprctl")
        .args(["eval", code])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status();
}

/// Lua that shows the special workspace, unless it is already shown (like
/// SUPER + I in config/caelestia/hypr-user.lua).
const OPEN_SPECIAL: &str = r#"local a = hl.get_active_special_workspace()
if not (a and a.name == "special:nixcfg") then hl.dispatch(hl.dsp.focus({ workspace = "special:nixcfg" })) end"#;

/// Show the nixcfg window: bring its special workspace up, or focus it where
/// it is, or open a new one attached to the session.
pub fn show() {
    let clients: Vec<serde_json::Value> = Command::new("hyprctl")
        .args(["clients", "-j"])
        .stdin(Stdio::null())
        .output()
        .ok()
        .and_then(|o| serde_json::from_slice(&o.stdout).ok())
        .unwrap_or_default();
    for client in &clients {
        if client.get("class").and_then(|c| c.as_str()) != Some(WINDOW_CLASS) {
            continue;
        }
        let address = client.get("address").and_then(|a| a.as_str()).unwrap_or("");
        let focus = format!(r#"hl.dispatch(hl.dsp.focus({{ window = "address:{address}" }}))"#);
        let workspace = client.pointer("/workspace/name").and_then(|n| n.as_str());
        if workspace == Some(SPECIAL) {
            hypr_lua(&format!("{OPEN_SPECIAL}\n{focus}"));
        } else {
            hypr_lua(&focus);
        }
        return;
    }
    if in_hyprland() {
        // Like Caelestia's special workspaces: show it, then start the app on it.
        hypr_lua(OPEN_SPECIAL);
    }
    let nixcfg = crate::cfg::which("nixcfg")
        .or_else(|| std::env::current_exe().ok())
        .map_or_else(|| "nixcfg".into(), |p| p.to_string_lossy().into_owned());
    // Without these, the new nixcfg would think it is already in the session.
    let _ = Command::new("kitty")
        .args(["--class", WINDOW_CLASS, "--title", WINDOW_CLASS, &nixcfg])
        .env_remove("NIXCFG_SESSION")
        .env_remove("TMUX")
        .env_remove("TMUX_PANE")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .spawn();
}

/// Hide the window (its special workspace), when it is shown. Returns
/// whether nixcfg can be hidden at all (in its session, under Hyprland).
pub fn hide() -> bool {
    if !in_session() || !in_hyprland() {
        return false;
    }
    hypr_lua(
        r#"local a = hl.get_active_special_workspace()
if a and a.name == "special:nixcfg" then hl.dispatch(hl.dsp.workspace.toggle_special("nixcfg")) end"#,
    );
    true
}
