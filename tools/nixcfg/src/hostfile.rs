//! Read and edit the module imports of a Nix file.
//!
//! A module is turned on or off the way you would by hand: by commenting its
//! line in `imports` out. Hosts import top-level modules and group cores:
//!
//! ```nix
//! # nixos/hosts/<host>/configuration.nix
//! imports = [
//!   ./hardware-configuration.nix
//!   ./../../core.nix
//!
//!   ./../../modules/flatpak.nix           <- enabled
//!   # ./../../modules/jetbrains.nix       <- disabled
//!   ./../../modules/epita/core.nix        <- the epita group
//! ];
//! ```
//!
//! and a group's core.nix (a folder with a core.nix is a group) imports its
//! submodules, for every host that turns the group on. The host's own
//! packages are a plain environment.systemPackages list in its
//! configuration.nix, edited with modfile.

use std::collections::{BTreeSet, HashMap, HashSet};
use std::path::Path;
use std::sync::LazyLock;

use regex::Regex;

use crate::text::{join, leading_ws, lines, normpath, posix, relpath};

/// An import line: "#"s (commented out), a relative path to a .nix file, and
/// an optional trailing comment.
static IMPORT: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
        r"^(?P<indent>\s*)(?P<hashes>(?:#\s*)*)(?P<path>\.{1,2}/[\w./-]*\.nix)(?P<comment>\s+#.*)?\s*$",
    )
    .unwrap()
});
static IMPORTS: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^\s*imports\s*=\s*\[\s*$").unwrap());

const PACKAGES_BLOCK: [&str; 4] = [
    "",
    "  # Packages for this host only",
    "  environment.systemPackages = with pkgs; [",
    "  ];",
];

#[derive(Clone, Debug)]
pub struct Import {
    pub line: usize, // 0-based
    pub name: String, // module name: path under nixos/modules without .nix
    pub enabled: bool,
    pub indent: String,
    pub path: String,
    pub comment: String,
}

/// The lines of "imports = [" and of its closing "]".
fn imports_block(lines: &[String]) -> Option<(usize, usize)> {
    block_of(lines, &IMPORTS)
}

fn block_of(lines: &[String], start: &Regex) -> Option<(usize, usize)> {
    for (s, line) in lines.iter().enumerate() {
        if start.is_match(line) {
            for (e, line) in lines.iter().enumerate().skip(s + 1) {
                if line.trim().starts_with(']') {
                    return Some((s, e));
                }
            }
        }
    }
    None
}

/// The module a path in a file of folder `here` points to, if any.
fn module_name(path: &str, here: &Path, modules_dir: &Path) -> Option<String> {
    let target = normpath(&here.join(path));
    let rel = target.strip_prefix(modules_dir).ok()?;
    let rel = posix(rel);
    if rel.is_empty() {
        return None;
    }
    let base = rel.rsplit('/').next().unwrap_or("");
    Some(if base != ".nix" { rel.strip_suffix(".nix").unwrap_or(&rel).to_string() } else { rel })
}

/// The module imports of a file in folder `here` (others are ignored).
pub fn parse(text: &str, here: &Path, modules_dir: &Path) -> Vec<Import> {
    let lines = lines(text);
    let Some((start, end)) = imports_block(&lines) else { return vec![] };
    let mut found = Vec::new();
    for (n, line) in lines.iter().enumerate().take(end).skip(start + 1) {
        if let Some(m) = IMPORT.captures(line)
            && let Some(name) = module_name(&m["path"], here, modules_dir)
        {
            found.push(Import {
                line: n,
                name,
                enabled: m["hashes"].is_empty(),
                indent: m["indent"].to_string(),
                path: m["path"].to_string(),
                comment: m.name("comment").map_or("", |c| c.as_str()).to_string(),
            });
        }
    }
    found
}

/// The modules imported (not commented out), in file order.
pub fn enabled(text: &str, here: &Path, modules_dir: &Path) -> Vec<String> {
    parse(text, here, modules_dir).into_iter().filter(|i| i.enabled).map(|i| i.name).collect()
}

fn line_for(indent: &str, on: bool, path: &str, comment: &str) -> String {
    format!("{indent}{}{path}{comment}", if on { "" } else { "# " })
}

/// Comment and uncomment import lines so that exactly `chosen` are on.
///
/// Existing lines keep their place, path and comment; a chosen module
/// without a line gets one, next to the modules of its folder or at the end
/// of the list. Commented lines of modules whose file is gone are dropped.
pub fn update<K: Ord>(
    text: &str,
    here: &Path,
    modules_dir: &Path,
    chosen: &[String],
    exists: impl Fn(&str) -> bool,
    sort_key: impl Fn(&str) -> K,
) -> Result<String, String> {
    let mut text = text.to_string();
    if !text.ends_with('\n') {
        text.push('\n');
    }
    let mut lines = lines(&text);
    let block = match imports_block(&lines) {
        Some(b) => b,
        None => {
            text = add_imports_block(&text);
            lines = crate::text::lines(&text);
            imports_block(&lines).ok_or("no `imports = [` list, and no place to add one")?
        }
    };

    let found = parse(&text, here, modules_dir);
    let have: HashSet<&str> = found.iter().map(|i| i.name.as_str()).collect();
    let mut drop = HashSet::new();
    for i in &found {
        let on = chosen.contains(&i.name);
        if !on && !exists(&i.name) {
            drop.insert(i.line);
        } else if on != i.enabled {
            // Remove every "#" level, or comment the line once.
            lines[i.line] = line_for(&i.indent, on, &i.path, &i.comment);
        }
    }

    let indent = match found.first() {
        Some(f) => f.indent.clone(),
        None => format!("{}  ", leading_ws(&lines[block.0])),
    };
    let mut missing: Vec<&String> = chosen.iter().filter(|n| !have.contains(n.as_str())).collect();
    missing.sort_by_key(|n| sort_key(n));
    let mut inserts: HashMap<usize, Vec<String>> = HashMap::new();
    for name in missing {
        let mut path = relpath(&modules_dir.join(format!("{name}.nix")), here);
        if !path.starts_with("../") {
            path = format!("./{path}");
        }
        if found.first().is_some_and(|f| f.path.starts_with("./../")) {
            path = format!("./{path}"); // the "./../../modules/" style of host files
        }
        let folder = name.rsplit_once('/').map_or("", |(f, _)| f);
        let same = found
            .iter()
            .filter(|i| i.name.rsplit_once('/').map_or("", |(f, _)| f) == folder)
            .map(|i| i.line)
            .max();
        let at = same.map_or(block.1, |s| s + 1);
        inserts.entry(at).or_default().push(line_for(&indent, true, &path, ""));
    }

    let mut out = Vec::new();
    for (n, line) in lines.into_iter().enumerate() {
        if let Some(ins) = inserts.remove(&n) {
            out.extend(ins);
        }
        if !drop.contains(&n) {
            out.push(line);
        }
    }
    Ok(join(&out))
}

/// Add an empty imports list at the top of the module's attribute set.
fn add_imports_block(text: &str) -> String {
    let mut lines = lines(text);
    for n in 0..lines.len() {
        let s = lines[n].trim();
        if s == "{" || (s.ends_with(": {") && n == 0) {
            lines.splice(n + 1..n + 1, ["  imports = [", "  ];", ""].map(String::from));
            break;
        }
    }
    join(&lines)
}

/// Add an empty environment.systemPackages list before the last "}".
pub fn add_packages_block(text: &str) -> String {
    let mut lines = crate::text::lines(text.trim_end_matches('\n'));
    if let Some(n) = lines.iter().rposition(|l| l.trim() == "}") {
        lines.splice(n..n, PACKAGES_BLOCK.map(String::from));
    }
    join(&lines)
}

// Desktops (nixos/modules/desktop) are chosen per host by a list of names,
// with a commented line for each one that is off, and an optional default:
//
//     desktop.enabled = [
//       "caelestia"
//       # "kde"
//     ];
//     desktop.defaultSession = "caelestia";
static DESKTOPS: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^(?P<indent>\s*)desktop\.enabled\s*=\s*\[\s*$").unwrap());
static DESKTOP: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"^(?P<indent>\s*)(?P<hashes>(?:#\s*)*)"(?P<name>[\w-]+)"(?P<comment>\s+#.*)?\s*$"#).unwrap()
});
static DEFAULT_SESSION: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r#"^(?P<head>\s*desktop\.defaultSession\s*=\s*)(?:"(?P<name>[\w-]*)"|null)(?P<tail>\s*;.*)$"#)
        .unwrap()
});

struct Desktop {
    line: usize,
    name: String,
    enabled: bool,
    indent: String,
    comment: String,
}

fn parse_desktops(lines: &[String]) -> Vec<Desktop> {
    let Some((start, end)) = block_of(lines, &DESKTOPS) else { return vec![] };
    (start + 1..end)
        .filter_map(|n| {
            DESKTOP.captures(&lines[n]).map(|m| Desktop {
                line: n,
                name: m["name"].to_string(),
                enabled: m["hashes"].is_empty(),
                indent: m["indent"].to_string(),
                comment: m.name("comment").map_or("", |c| c.as_str()).to_string(),
            })
        })
        .collect()
}

/// The desktops the host turns on, in file order.
pub fn desktops(text: &str) -> Vec<String> {
    desktops_of(&lines(text))
}

fn desktops_of(lines: &[String]) -> Vec<String> {
    parse_desktops(lines).into_iter().filter(|d| d.enabled).map(|d| d.name).collect()
}

/// desktop.defaultSession if set (None for null), else the first desktop
/// (Nix's default).
pub fn default_session(text: &str) -> Option<String> {
    for line in lines(text) {
        if let Some(m) = DEFAULT_SESSION.captures(&line) {
            return m.name("name").map(|n| n.as_str().to_string());
        }
    }
    desktops(text).into_iter().next()
}

/// Comment and uncomment the lines of desktop.enabled so that exactly
/// `chosen` are on. A desktop of `known` without a line gets one (commented
/// when off), and the list is added if missing. If the default session is
/// turned off, it moves to the first desktop left on (or null).
pub fn update_desktops(text: &str, chosen: &[String], known: &[String]) -> String {
    let mut text = text.to_string();
    if !text.ends_with('\n') {
        text.push('\n');
    }
    let mut lines = lines(&text);
    if block_of(&lines, &DESKTOPS).is_none() {
        if chosen.is_empty() {
            return text;
        }
        lines = crate::text::lines(&add_desktops_block(&text));
    }
    let (start, end) = block_of(&lines, &DESKTOPS).expect("desktop list just added");
    let found = parse_desktops(&lines);
    for d in &found {
        let on = chosen.contains(&d.name);
        if on != d.enabled {
            lines[d.line] = format!("{}{}\"{}\"{}", d.indent, if on { "" } else { "# " }, d.name, d.comment);
        }
    }
    let have: HashSet<&str> = found.iter().map(|d| d.name.as_str()).collect();
    let indent = match found.first() {
        Some(d) => d.indent.clone(),
        None => format!("{}  ", &DESKTOPS.captures(&lines[start]).unwrap()["indent"]),
    };
    let missing: Vec<String> = known
        .iter()
        .filter(|n| !have.contains(n.as_str()))
        .collect::<BTreeSet<_>>()
        .into_iter()
        .map(|n| format!("{indent}{}\"{n}\"", if chosen.contains(n) { "" } else { "# " }))
        .collect();
    lines.splice(end..end, missing);

    for n in 0..lines.len() {
        let Some(m) = DEFAULT_SESSION.captures(&lines[n]) else { continue };
        let name = m.name("name").map(|n| n.as_str().to_string());
        if name.is_none_or(|name| !chosen.contains(&name)) {
            let value = desktops_of(&lines).first().map_or("null".to_string(), |d| format!("\"{d}\""));
            lines[n] = format!("{}{value}{}", &m["head"], &m["tail"]);
        }
    }
    join(&lines)
}

/// Set desktop.defaultSession, adding the line after the list if needed.
pub fn set_default_session(text: &str, name: &str) -> Result<String, String> {
    let mut lines = lines(text);
    for n in 0..lines.len() {
        if let Some(m) = DEFAULT_SESSION.captures(&lines[n]) {
            lines[n] = format!("{}\"{name}\"{}", &m["head"], &m["tail"]);
            return Ok(join(&lines));
        }
    }
    let (start, end) = block_of(&lines, &DESKTOPS).ok_or("no `desktop.enabled = [` list")?;
    let indent = DESKTOPS.captures(&lines[start]).unwrap()["indent"].to_string();
    lines.insert(end + 1, format!("{indent}desktop.defaultSession = \"{name}\";"));
    Ok(join(&lines))
}

/// Add an empty desktop.enabled list after the imports (or before the last "}").
fn add_desktops_block(text: &str) -> String {
    let mut lines = lines(text.trim_end_matches('\n'));
    let new = [
        "",
        "  # Desktops: all selectable on the login screen (or use `nixcfg`)",
        "  desktop.enabled = [",
        "  ];",
    ]
    .map(String::from);
    let at = match imports_block(&lines) {
        Some((_, end)) => end + 1,
        None => lines.iter().rposition(|l| l.trim() == "}").unwrap_or(lines.len()),
    };
    lines.splice(at..at, new);
    join(&lines)
}
