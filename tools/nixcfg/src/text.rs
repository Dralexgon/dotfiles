//! Small string and path helpers that behave like the Python ones the legacy
//! version used (str.splitlines, str.strip, os.path.normpath, relpath...), so
//! both versions edit files the same way.

use std::path::{Component, Path, PathBuf};

/// `str.splitlines()`: lines without their ending, no empty last line.
pub fn lines(text: &str) -> Vec<String> {
    text.lines().map(str::to_string).collect()
}

/// `str.splitlines(keepends=True)`.
pub fn lines_keep(text: &str) -> Vec<String> {
    text.split_inclusive('\n').map(str::to_string).collect()
}

/// `re.match(r"\s*", line).group()`.
pub fn leading_ws(line: &str) -> &str {
    let rest = line.trim_start();
    &line[..line.len() - rest.len()]
}

/// `"\n".join(lines) + "\n"`.
pub fn join(lines: &[String]) -> String {
    let mut out = lines.join("\n");
    out.push('\n');
    out
}

pub fn char_len(s: &str) -> usize {
    s.chars().count()
}

/// `" " * max(min, width - len(s))`: the padding after a column.
pub fn pad(s: &str, width: usize, min: usize) -> String {
    " ".repeat(width.saturating_sub(char_len(s)).max(min))
}

/// `os.path.normpath`, lexically.
pub fn normpath(path: &Path) -> PathBuf {
    let mut out: Vec<Component> = Vec::new();
    for c in path.components() {
        match c {
            Component::CurDir => {}
            Component::ParentDir => match out.last() {
                Some(Component::Normal(_)) => {
                    out.pop();
                }
                Some(Component::RootDir) => {}
                _ => out.push(c),
            },
            _ => out.push(c),
        }
    }
    out.iter().collect()
}

/// `os.path.relpath(target, start)` for two absolute paths.
pub fn relpath(target: &Path, start: &Path) -> String {
    let (target, start) = (normpath(target), normpath(start));
    let t: Vec<_> = target.components().collect();
    let s: Vec<_> = start.components().collect();
    let common = t.iter().zip(&s).take_while(|(a, b)| a == b).count();
    let mut parts: Vec<String> = vec!["..".to_string(); s.len() - common];
    parts.extend(t[common..].iter().map(|c| c.as_os_str().to_string_lossy().into_owned()));
    if parts.is_empty() { ".".into() } else { parts.join("/") }
}

/// A path as text with "/" separators (`Path.as_posix()`).
pub fn posix(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}

/// A path under `root` as "a/b" (`path.relative_to(root).as_posix()`).
pub fn relative(path: &Path, root: &Path) -> Option<String> {
    path.strip_prefix(root).ok().map(posix)
}
