//! Read and edit the environment.systemPackages lists of a module file.
//!
//! Module files stay Nix code: a package is one line of a list, and it is
//! disabled by commenting that line out, the same way you would by hand:
//!
//! ```nix
//! environment.systemPackages = with pkgs; [
//!   kitty # Terminal          <- enabled
//!   # lutris                  <- disabled
//!   # Ricing                  <- a comment (capitalized or several words)
//!   (python3.withPackages (ps: [ ps.requests ]))   <- read-only expression
//! ];
//! ```

use std::sync::LazyLock;

use regex::Regex;

use crate::text::{leading_ws, lines, lines_keep};

static DECLARATION: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"environment\.systemPackages\s*=").unwrap());
/// An item that is just an attribute path, with an optional trailing comment.
static ENABLED: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^(\s*)([A-Za-z_][\w'.-]*)\s*(#.*)?$").unwrap());
/// A commented-out attribute path: lowercase, one word, "#" then at most one
/// space (deeper indentation after "#" is the inside of a commented block).
static DISABLED: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^(\s*)# ?([a-z0-9_][\w'.-]*)\s*(#.*)?$").unwrap());
static COMMENT_MARK: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^# ?").unwrap());

#[derive(Clone, Debug, PartialEq)]
pub struct Entry {
    pub line: usize, // 0-based line number in the file
    pub name: String, // attribute path, or the first line of an expression
    pub enabled: bool,
    pub editable: bool, // false for expressions (overrides, withPackages...)
    pub comment: String,
}

/// One environment.systemPackages list.
#[derive(Debug)]
pub struct Block {
    /// Line of the closing "]"; None when the list closes at the end of an
    /// item line ("foo ]"), which leaves no line to insert before.
    pub close: Option<usize>,
    pub indent: String, // indentation of its items
    pub entries: Vec<Entry>,
}

/// The line without its comment (a "#" outside of a string).
pub fn code_part(line: &str) -> &str {
    let mut in_string = false;
    for (i, c) in line.char_indices() {
        if c == '"' {
            in_string = !in_string;
        } else if c == '#' && !in_string {
            return &line[..i];
        }
    }
    line
}

fn depth_change(code: &str) -> i64 {
    code.chars()
        .map(|c| match c {
            '[' | '(' | '{' => 1,
            ']' | ')' | '}' => -1,
            _ => 0,
        })
        .sum()
}

pub fn parse(text: &str) -> Vec<Block> {
    let lines = lines(text);
    let mut blocks = Vec::new();
    let mut i = 0;
    while i < lines.len() {
        let code = code_part(&lines[i]);
        let Some(m) = DECLARATION.find(code) else {
            i += 1;
            continue;
        };
        // The list starts at the first "[" after "=", maybe on a later line.
        let mut rest = code[m.end()..].to_string();
        while !rest.contains('[') && i + 1 < lines.len() {
            i += 1;
            rest = code_part(&lines[i]).to_string();
        }
        let Some(open) = rest.find('[') else { break };
        let mut depth = 1 + depth_change(&rest[open + 1..]);
        if depth <= 0 {
            // "[ ]" on one line: nothing to list
            i += 1;
            continue;
        }
        let mut items: Vec<(usize, bool)> = Vec::new(); // (line, is code) at depth 1
        i += 1;
        while i < lines.len() && depth > 0 {
            let code = code_part(&lines[i]).trim();
            if depth == 1 && code.starts_with(']') {
                break;
            }
            if depth == 1 {
                items.push((i, !code.is_empty()));
            }
            depth += depth_change(code);
            i += 1;
        }
        if depth > 0 && i >= lines.len() {
            break;
        }
        let closed_inline = depth == 0;

        let reference = items
            .iter()
            .find(|(_, code)| *code)
            .or(items.first())
            .map_or(i, |(n, _)| *n);
        let mut indent = lines.get(reference).map_or("", |l| leading_ws(l)).to_string();
        if items.is_empty() && !closed_inline {
            indent = format!("{}  ", leading_ws(&lines[i]));
        }
        let mut block = Block { close: (!closed_inline).then_some(i), indent, entries: Vec::new() };
        for &(n, is_code) in &items {
            let line = &lines[n];
            if is_code {
                if let Some(c) = ENABLED.captures(line) {
                    block.entries.push(Entry {
                        line: n,
                        name: c[2].to_string(),
                        enabled: true,
                        editable: true,
                        comment: c.get(3).map_or("", |m| m.as_str()).to_string(),
                    });
                } else {
                    block.entries.push(Entry {
                        line: n,
                        name: line.trim().to_string(),
                        enabled: true,
                        editable: false,
                        comment: String::new(),
                    });
                }
            } else if let Some(c) = DISABLED.captures(line)
                && c[1] == block.indent
            {
                block.entries.push(Entry {
                    line: n,
                    name: c[2].to_string(),
                    enabled: false,
                    editable: true,
                    comment: c.get(3).map_or("", |m| m.as_str()).to_string(),
                });
            }
        }
        blocks.push(block);
        // Past its "]" line. A list closed inline already left i on the next
        // line, which may start another list.
        if !closed_inline {
            i += 1;
        }
    }
    blocks
}

pub fn entries(text: &str) -> Vec<Entry> {
    parse(text).into_iter().flat_map(|b| b.entries).collect()
}

fn replace_line(text: &str, n: usize, new: Option<String>) -> String {
    let mut lines = lines_keep(text);
    match new {
        None => {
            lines.remove(n);
        }
        Some(new) => {
            let ending = if lines[n].ends_with('\n') { "\n" } else { "" };
            lines[n] = new + ending;
        }
    }
    lines.concat()
}

pub fn toggle(text: &str, entry: &Entry) -> String {
    let line = lines(text)[entry.line].clone();
    let indent = leading_ws(&line);
    let body = &line[indent.len()..];
    let new = if entry.enabled {
        format!("{indent}# {body}")
    } else {
        format!("{indent}{}", COMMENT_MARK.replace(body, ""))
    };
    replace_line(text, entry.line, Some(new))
}

pub fn remove(text: &str, entry: &Entry) -> String {
    replace_line(text, entry.line, None)
}

/// Add a package line at the end of the first list, with an optional
/// description as a trailing comment ("kitty # Terminal").
///
/// Returns the new text and the line of the package, or None when the
/// module has no environment.systemPackages list.
pub fn add(text: &str, attr: &str, comment: &str) -> Option<(String, usize)> {
    let blocks = parse(text);
    let block = blocks.iter().find(|b| b.close.is_some())?;
    let close = block.close.unwrap();
    let mut lines = lines_keep(text);
    let comment = comment.split_whitespace().collect::<Vec<_>>().join(" ");
    let comment = comment.trim_start_matches(['#', ' ']);
    let line = if comment.is_empty() { attr.to_string() } else { format!("{attr} # {comment}") };
    lines.insert(close, format!("{}{line}\n", block.indent));
    Some((lines.concat(), close))
}
