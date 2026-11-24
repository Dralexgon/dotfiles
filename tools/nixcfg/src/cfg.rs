//! The dotfiles as nixcfg sees them: hosts, modules, groups and what each host
//! turns on. Everything stays Nix code and is toggled by commenting lines out
//! (see hostfile.rs and modfile.rs).

use std::collections::BTreeSet;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::LazyLock;

use regex::Regex;

use crate::text::{posix, relative};
use crate::{hostfile, modfile};

pub fn home() -> PathBuf {
    std::env::var_os("HOME").map_or_else(|| PathBuf::from("/"), PathBuf::from)
}

pub static DOTFILES: LazyLock<PathBuf> = LazyLock::new(|| {
    let path = std::env::var_os("NIXCFG_DOTFILES").map_or_else(|| home().join("dotfiles"), PathBuf::from);
    std::path::absolute(&path).unwrap_or(path)
});
pub static HOSTS_DIR: LazyLock<PathBuf> = LazyLock::new(|| DOTFILES.join("nixos/hosts"));
pub static MODULES_DIR: LazyLock<PathBuf> = LazyLock::new(|| DOTFILES.join("nixos/modules"));

/// A module is any .nix file under nixos/modules, named by its path without
/// .nix ("gnome", "epita/core", "epita/c").
pub static MODULE_NAME: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)*$").unwrap());

pub const MODULE_TEMPLATE: &str = "{ pkgs, ... }:\n\n{\n  environment.systemPackages = with pkgs; [\n  ];\n}\n";

/// Each rebuild adds a system-<n>-link here; the profile points to the newest.
pub const SYSTEM_PROFILE: &str = "/nix/var/nix/profiles/system";

/// nixos/core.nix, imported by every host: shown as an always-on module, so
/// its packages can be toggled like any module's.
pub const CORE: &str = "core";
/// nixos/hosts/<host>/configuration.nix, shown as an always-on module of its
/// host (right after core), so the host's own file can be browsed and edited.
pub const HOST_PREFIX: &str = "hosts/";
/// nixos/modules/desktop: a group imported by core.nix (so always on), whose
/// desktops are picked per host in its desktop.enabled list (see hostfile.rs),
/// not in imports. desktop/default.nix holds the options and the login screen.
pub const DESKTOP_CORE: &str = "desktop/default";

pub fn list_hosts() -> Vec<String> {
    let mut hosts: Vec<String> = fs::read_dir(&*HOSTS_DIR)
        .into_iter()
        .flatten()
        .flatten()
        .filter(|e| e.path().join("configuration.nix").exists())
        .map(|e| e.file_name().to_string_lossy().into_owned())
        .collect();
    hosts.sort();
    hosts
}

/// Every .nix file under a folder, subfolders included (like Path.rglob).
pub fn nix_files(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    let Ok(entries) = fs::read_dir(dir) else { return out };
    for entry in entries.flatten() {
        let path = entry.path();
        let is_dir = entry.file_type().is_ok_and(|t| t.is_dir());
        if path.extension().is_some_and(|e| e == "nix") {
            out.push(path.clone());
        }
        if is_dir {
            out.extend(nix_files(&path));
        }
    }
    out
}

pub fn list_modules() -> Vec<String> {
    let mut names: Vec<String> = nix_files(&MODULES_DIR)
        .iter()
        .filter_map(|p| relative(&p.with_extension(""), &MODULES_DIR))
        .collect();
    names.sort();
    names
}

pub fn host_module(host: &str) -> String {
    format!("{HOST_PREFIX}{host}")
}

pub fn is_host_module(name: &str) -> bool {
    name.starts_with(HOST_PREFIX)
}

pub fn desktop_name(name: &str) -> &str {
    name.strip_prefix("desktop/").unwrap_or(name)
}

pub fn list_desktops() -> Vec<String> {
    list_modules().into_iter().filter(|n| group_core(n).as_deref() == Some(DESKTOP_CORE)).collect()
}

/// core, the host's configuration and the desktop group: always on, can't be deleted.
pub fn is_pinned(name: &str) -> bool {
    name == CORE || name == DESKTOP_CORE || is_host_module(name)
}

pub fn module_path(name: &str) -> PathBuf {
    if name == CORE {
        return DOTFILES.join("nixos/core.nix");
    }
    if let Some(host) = name.strip_prefix(HOST_PREFIX) {
        return host_path(host);
    }
    MODULES_DIR.join(format!("{name}.nix"))
}

pub fn read(path: &Path) -> String {
    fs::read_to_string(path).unwrap_or_default()
}

pub fn module_entries(name: &str) -> Vec<modfile::Entry> {
    fs::read_to_string(module_path(name)).map(|t| modfile::entries(&t)).unwrap_or_default()
}

// A folder with a core.nix is a group (see hostfile.rs): its core switches
// the whole group, and each submodule is toggled on its own. The desktop
// folder is a group too, with default.nix as its core.

/// The core of a folder, if it is a group.
pub fn folder_core(folder: &str) -> Option<String> {
    let core = if folder == "desktop" { DESKTOP_CORE.to_string() } else { format!("{folder}/core") };
    module_path(&core).exists().then_some(core)
}

/// The core of the group a submodule is in ("epita/c" -> "epita/core").
pub fn group_core(name: &str) -> Option<String> {
    let (folder, _) = name.rsplit_once('/')?;
    folder_core(folder).filter(|core| core != name)
}

pub fn is_group(name: &str) -> bool {
    name.rsplit_once('/').is_some_and(|(folder, _)| folder_core(folder).as_deref() == Some(name))
}

pub fn group_label(core: &str) -> &str {
    core.rsplit_once('/').map_or("", |(f, _)| f)
}

pub fn is_active(name: &str, enabled: &[String]) -> bool {
    if is_pinned(name) {
        return true;
    }
    let core = group_core(name);
    enabled.iter().any(|n| n == name)
        && core.is_none_or(|c| is_pinned(&c) || enabled.contains(&c))
}

/// Sort groups by folder name, with their submodules right after them (and
/// core.nix first).
pub fn display_key(name: &str) -> (String, bool, String) {
    if name == CORE || is_host_module(name) {
        return (String::new(), false, if is_host_module(name) { name.into() } else { String::new() });
    }
    if let Some((folder, base)) = name.rsplit_once('/')
        && let Some(core) = folder_core(folder)
    {
        return (folder.into(), name != core, base.into());
    }
    (name.into(), false, String::new())
}

pub fn host_path(host: &str) -> PathBuf {
    HOSTS_DIR.join(host).join("configuration.nix")
}

fn imported(path: &Path) -> Vec<String> {
    match fs::read_to_string(path) {
        Ok(text) => hostfile::enabled(&text, path.parent().unwrap(), &MODULES_DIR),
        Err(_) => vec![],
    }
}

/// The submodules a group's core.nix imports (for every host).
pub fn group_subs(core: &str) -> Vec<String> {
    imported(&module_path(core)).into_iter().filter(|n| group_core(n).as_deref() == Some(core)).collect()
}

/// The modules the host imports, the submodules chosen in every group's
/// core.nix (active only when the host imports that core), and the host's
/// desktops ("desktop/gnome").
pub fn load_state(host: &str) -> Vec<String> {
    let mut modules = imported(&host_path(host));
    for core in list_modules().into_iter().filter(|n| is_group(n)) {
        if core != DESKTOP_CORE {
            for n in group_subs(&core) {
                if !modules.contains(&n) {
                    modules.push(n);
                }
            }
        }
    }
    if let Ok(text) = fs::read_to_string(host_path(host)) {
        modules.extend(hostfile::desktops(&text).into_iter().map(|n| format!("desktop/{n}")));
    }
    modules
}

fn updated_imports(path: &Path, chosen: &[String]) -> Result<String, String> {
    let text = fs::read_to_string(path).map_err(|e| e.to_string())?;
    hostfile::update(&text, path.parent().unwrap(), &MODULES_DIR, chosen, |n| module_path(n).exists(), display_key)
}

/// Write the host's own imports (submodules live in their core.nix) and its desktops.
pub fn save_state(host: &str, modules: &[String]) -> Result<(), String> {
    let path = host_path(host);
    let own: Vec<String> = modules.iter().filter(|n| group_core(n).is_none()).cloned().collect();
    let new = updated_imports(&path, &own)?;
    let chosen: Vec<String> = modules
        .iter()
        .filter(|n| group_core(n).as_deref() == Some(DESKTOP_CORE))
        .map(|n| desktop_name(n).to_string())
        .collect();
    let known: Vec<String> = list_desktops().iter().map(|n| desktop_name(n).to_string()).collect();
    let new = hostfile::update_desktops(&new, &chosen, &known);
    if new != read(&path) {
        fs::write(&path, new).map_err(|e| e.to_string())?;
    }
    Ok(())
}

/// The core.nix of a group, importing exactly `subs`.
pub fn core_text(core: &str, subs: &[String]) -> Result<String, String> {
    updated_imports(&module_path(core), subs)
}

/// The packages of the host's own environment.systemPackages list.
pub fn host_entries(host: &str) -> Vec<modfile::Entry> {
    modfile::entries(&read(&host_path(host))).into_iter().filter(|e| e.editable).collect()
}

/// The default host imports /etc/nixos/hardware-configuration.nix.
pub fn flake_args(host: &str) -> Vec<String> {
    if host == "default" { vec!["--impure".into()] } else { vec![] }
}

/// The most useful line of a Nix error.
pub fn nix_error(stderr: &str) -> String {
    let errors: Vec<&str> = stderr.lines().filter(|l| l.contains("error:")).map(str::trim).collect();
    match errors.last() {
        Some(e) => e.to_string(),
        None => stderr.trim().lines().last().unwrap_or("unknown error").to_string(),
    }
}

fn output(cmd: &mut Command) -> Option<std::process::Output> {
    cmd.stdin(Stdio::null()).output().ok()
}

/// Check a module file with Nix. Returns an error message, or None.
///
/// The syntax is always checked; then the config of every host that uses the
/// module is evaluated, which catches unknown package names.
pub fn check_module(name: &str) -> Option<String> {
    let path = module_path(name);
    let Some(out) = output(Command::new("nix-instantiate").arg("--parse").arg(&path)) else {
        return Some("nix-instantiate not found".into());
    };
    if !out.status.success() {
        return Some(nix_error(&String::from_utf8_lossy(&out.stderr)));
    }
    let hosts = match name.strip_prefix(HOST_PREFIX) {
        Some(host) => vec![host.to_string()],
        None => list_hosts(),
    };
    for host in hosts {
        if !is_active(name, &load_state(&host)) {
            continue;
        }
        let attr = format!("{}#nixosConfigurations.{host}.config.environment.systemPackages", posix(&DOTFILES));
        let out = output(
            Command::new("nix")
                .args(["eval", "--json"])
                .args(flake_args(&host))
                .arg(attr)
                .args(["--apply", "map (p: p.name)"]),
        );
        let Some(out) = out else { return Some("nix not found".into()) };
        if !out.status.success() {
            return Some(format!("{host}: {}", nix_error(&String::from_utf8_lossy(&out.stderr))));
        }
    }
    None
}

/// `shutil.which`.
pub fn which(name: &str) -> Option<PathBuf> {
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths).map(|p| p.join(name)).find(|p| {
            use std::os::unix::fs::PermissionsExt;
            p.metadata().is_ok_and(|m| m.is_file() && m.permissions().mode() & 0o111 != 0)
        })
    })
}

pub fn editor_command(path: &Path, line: Option<usize>) -> Vec<String> {
    let editor = std::env::var("EDITOR")
        .ok()
        .filter(|e| !e.is_empty())
        .or_else(|| which("nvim").map(|p| posix(&p)))
        .unwrap_or_else(|| "vi".into());
    let path = posix(path);
    match line {
        None => vec![editor, path],
        Some(line) => {
            let base = Path::new(&editor).file_name().map(|n| n.to_string_lossy().into_owned()).unwrap_or_default();
            if base == "hx" || base == "helix" {
                vec![editor, format!("{path}:{line}")]
            } else {
                vec![editor, format!("+{line}"), path]
            }
        }
    }
}

pub fn notify_desktop(summary: &str, body: &str, failed: bool) {
    if which("notify-send").is_some() {
        let _ = Command::new("notify-send")
            .args(["--app-name=nixcfg", "--icon=nix-snowflake"])
            .arg(format!("--urgency={}", if failed { "critical" } else { "normal" }))
            .args([summary, body])
            .status();
    }
}

pub fn hostname() -> String {
    let mut buf = [0u8; 256];
    // SAFETY: the buffer is valid for its length; gethostname null-terminates it.
    let ok = unsafe { libc::gethostname(buf.as_mut_ptr().cast(), buf.len()) } == 0;
    if !ok {
        return String::new();
    }
    let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
    String::from_utf8_lossy(&buf[..end]).into_owned()
}

/// The flake's direct inputs when some of them point to a local repo that isn't on
/// this machine (`git+file://`, like my private dotfiles), None when all can be fetched.
pub fn reachable_inputs() -> Option<Vec<String>> {
    let lock: serde_json::Value = serde_json::from_str(&std::fs::read_to_string(DOTFILES.join("flake.lock")).ok()?).ok()?;
    let nodes = lock.get("nodes")?;
    let root = nodes.get(lock.get("root")?.as_str()?)?.get("inputs")?.as_object()?;
    let mut missing = false;
    let mut names = Vec::new();
    for (name, node) in root {
        let local = node.as_str().and_then(|n| nodes.get(n)).and_then(|n| n.get("original")).and_then(|o| {
            (o.get("type")?.as_str()? == "git").then(|| o.get("url")?.as_str()?.strip_prefix("file://").map(PathBuf::from))?
        });
        match local {
            Some(path) if !path.exists() => missing = true,
            _ => names.push(name.clone()),
        }
    }
    missing.then_some(names)
}

pub fn has_nh() -> bool {
    which("nh").is_some()
}

pub fn nh_args(host: &str) -> Vec<String> {
    let mut args = vec![posix(&DOTFILES), "--hostname".into(), host.into()];
    args.extend(flake_args(host));
    args
}

pub struct Generation {
    pub number: u32,
    pub date: String,
    pub version: String,
    pub kernel: String,
    pub current: bool,
    pub running: bool,
}

/// This machine's system generations, newest first.
pub fn list_generations() -> Vec<Generation> {
    static LINK: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^system-(\d+)-link$").unwrap());
    let profile = Path::new(SYSTEM_PROFILE);
    // By link name: several generations can share a store path.
    let current = fs::read_link(profile).ok().and_then(|p| p.file_name().map(|n| n.to_owned()));
    let running = fs::canonicalize("/run/current-system").ok();
    let mut generations = Vec::new();
    for entry in fs::read_dir(profile.parent().unwrap()).into_iter().flatten().flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        let Some(m) = LINK.captures(&name) else { continue };
        let link = entry.path();
        let path = fs::canonicalize(&link).unwrap_or_else(|_| link.clone());
        let version = fs::read_to_string(path.join("nixos-version")).map_or("?".into(), |v| v.trim().to_string());
        let kernel = match fs::read_dir(path.join("kernel-modules/lib/modules")) {
            Ok(dir) => dir.flatten().map(|e| e.file_name().to_string_lossy().into_owned()).collect::<Vec<_>>().join(" "),
            Err(_) => "?".into(),
        };
        let date = fs::symlink_metadata(&link)
            .and_then(|m| m.modified())
            .map(|t| chrono::DateTime::<chrono::Local>::from(t).format("%Y-%m-%d %H:%M").to_string())
            .unwrap_or_default();
        generations.push(Generation {
            number: m[1].parse().unwrap_or(0),
            date,
            version,
            kernel,
            current: current.as_deref() == Some(entry.file_name().as_os_str()),
            running: running.as_ref() == Some(&path),
        });
    }
    generations.sort_by_key(|g| std::cmp::Reverse(g.number));
    generations
}

/// [1, 2, 3, 5] -> "1–3, 5".
pub fn number_ranges(numbers: &[u32]) -> String {
    let mut sorted = numbers.to_vec();
    sorted.sort();
    let mut ranges: Vec<(u32, u32)> = Vec::new();
    for n in sorted {
        match ranges.last_mut() {
            Some(last) if n == last.1 + 1 => last.1 = n,
            _ => ranges.push((n, n)),
        }
    }
    ranges.iter().map(|(a, b)| if a == b { a.to_string() } else { format!("{a}–{b}") }).collect::<Vec<_>>().join(", ")
}

/// A path from the dotfiles (config/caelestia/hypr-vars.lua) or from ~.
pub fn display_path(path: &Path) -> String {
    if let Some(rel) = relative(path, &DOTFILES) {
        return rel;
    }
    if let Some(rel) = relative(path, &home()) {
        return format!("~/{rel}");
    }
    posix(path)
}

/// The modules mentioned by other module files (to warn before deleting one).
pub fn importers(path: &Path) -> Vec<String> {
    let needle = format!("/{}", path.file_name().unwrap_or_default().to_string_lossy());
    nix_files(&MODULES_DIR)
        .into_iter()
        .filter(|p| p != path && read(p).contains(&needle))
        .filter_map(|p| relative(&p, &MODULES_DIR))
        .collect()
}

/// Every module shown for a host: core, its configuration, the files and the
/// modules it imports, in display order.
pub fn module_names(host: &str, enabled: &[String]) -> Vec<String> {
    let mut names: BTreeSet<String> = list_modules().into_iter().collect();
    names.insert(CORE.into());
    names.insert(host_module(host));
    names.extend(enabled.iter().cloned());
    let mut names: Vec<String> = names.into_iter().collect();
    names.sort_by_cached_key(|n| display_key(n));
    names
}

pub fn git(args: &[&str]) -> bool {
    Command::new("git")
        .arg("-C")
        .arg(&*DOTFILES)
        .args(args)
        .stdin(Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
}
