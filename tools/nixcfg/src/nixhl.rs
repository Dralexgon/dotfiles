//! A small Nix syntax highlighter for the file preview, in the terminal's
//! ANSI colors (like Rich's ansi_dark theme did): comments, strings (with
//! multi-line '' strings and /* */ comments), keywords, paths and numbers.

use ratatui::style::{Color, Modifier, Style};
use ratatui::text::Span;

const KEYWORDS: &[&str] = &["let", "in", "with", "rec", "inherit", "if", "then", "else", "assert", "or"];
const CONSTANTS: &[&str] = &["true", "false", "null"];
const BUILTINS: &[&str] = &["import", "builtins", "throw", "abort", "map", "toString", "baseNameOf", "derivation"];

#[derive(Clone, Copy, PartialEq)]
enum State {
    Code,
    BlockComment,
    IndentString,
}

fn style_comment() -> Style {
    Style::default().fg(Color::DarkGray).add_modifier(Modifier::ITALIC)
}
fn style_string() -> Style {
    Style::default().fg(Color::Green)
}

/// The highlighted lines of a Nix file.
pub fn highlight(text: &str) -> Vec<Vec<Span<'static>>> {
    let mut state = State::Code;
    let mut out = Vec::new();
    for line in text.lines() {
        let mut spans: Vec<Span<'static>> = Vec::new();
        let chars: Vec<char> = line.chars().collect();
        let mut i = 0;
        let push = |spans: &mut Vec<Span<'static>>, s: String, st: Style| {
            if !s.is_empty() {
                spans.push(Span::styled(s, st));
            }
        };
        while i < chars.len() {
            match state {
                State::BlockComment => {
                    let start = i;
                    while i < chars.len() && !(chars[i] == '*' && chars.get(i + 1) == Some(&'/')) {
                        i += 1;
                    }
                    if i < chars.len() {
                        i += 2;
                        state = State::Code;
                    }
                    push(&mut spans, chars[start..i.min(chars.len())].iter().collect(), style_comment());
                }
                State::IndentString => {
                    let start = i;
                    loop {
                        if i >= chars.len() {
                            break;
                        }
                        if chars[i] == '\'' && chars.get(i + 1) == Some(&'\'') {
                            // ''' ''$ ''\ are escapes, '' alone ends the string
                            if matches!(chars.get(i + 2), Some('\'') | Some('$') | Some('\\')) {
                                i += 3;
                                continue;
                            }
                            i += 2;
                            state = State::Code;
                            break;
                        }
                        i += 1;
                    }
                    push(&mut spans, chars[start..i.min(chars.len())].iter().collect(), style_string());
                }
                State::Code => {
                    let c = chars[i];
                    let rest = |n: usize| chars.get(i + n).copied();
                    if c == '#' {
                        push(&mut spans, chars[i..].iter().collect(), style_comment());
                        i = chars.len();
                    } else if c == '/' && rest(1) == Some('*') {
                        state = State::BlockComment;
                        let start = i;
                        i += 2;
                        while i < chars.len() && !(chars[i] == '*' && chars.get(i + 1) == Some(&'/')) {
                            i += 1;
                        }
                        if i < chars.len() {
                            i += 2;
                            state = State::Code;
                        }
                        push(&mut spans, chars[start..i.min(chars.len())].iter().collect(), style_comment());
                    } else if c == '\'' && rest(1) == Some('\'') {
                        state = State::IndentString;
                        push(&mut spans, "''".into(), style_string());
                        i += 2;
                    } else if c == '"' {
                        let start = i;
                        i += 1;
                        while i < chars.len() && chars[i] != '"' {
                            if chars[i] == '\\' {
                                i += 1;
                            }
                            i += 1;
                        }
                        i = (i + 1).min(chars.len());
                        push(&mut spans, chars[start..i].iter().collect(), style_string());
                    } else if (c == '.' && matches!(rest(1), Some('/') | Some('.')))
                        || (c == '~' && rest(1) == Some('/'))
                        || (c == '<' && rest(1).is_some_and(|n| n.is_ascii_alphabetic()))
                    {
                        let start = i;
                        while i < chars.len() && !chars[i].is_whitespace() && !";)]}".contains(chars[i]) {
                            i += 1;
                        }
                        push(&mut spans, chars[start..i].iter().collect(), Style::default().fg(Color::Yellow));
                    } else if c.is_ascii_digit() {
                        let start = i;
                        while i < chars.len() && (chars[i].is_ascii_digit() || chars[i] == '.') {
                            i += 1;
                        }
                        push(&mut spans, chars[start..i].iter().collect(), Style::default().fg(Color::Cyan));
                    } else if c.is_alphabetic() || c == '_' {
                        let start = i;
                        while i < chars.len() && (chars[i].is_alphanumeric() || "_-'".contains(chars[i])) {
                            i += 1;
                        }
                        let word: String = chars[start..i].iter().collect();
                        // An attribute being set: "name =" or "a.b.c ="
                        let mut j = i;
                        while j < chars.len() && (chars[j] == '.' || chars[j].is_alphanumeric() || "_-'".contains(chars[j])) {
                            j += 1;
                        }
                        while j < chars.len() && chars[j] == ' ' {
                            j += 1;
                        }
                        let assigned = chars.get(j) == Some(&'=') && chars.get(j + 1) != Some(&'=');
                        let style = if KEYWORDS.contains(&word.as_str()) {
                            Style::default().fg(Color::Magenta).add_modifier(Modifier::BOLD)
                        } else if CONSTANTS.contains(&word.as_str()) || BUILTINS.contains(&word.as_str()) {
                            Style::default().fg(Color::Cyan)
                        } else if assigned {
                            Style::default().fg(Color::Blue)
                        } else {
                            Style::default()
                        };
                        push(&mut spans, word, style);
                    } else {
                        let start = i;
                        while i < chars.len()
                            && !chars[i].is_alphanumeric()
                            && !"#\"'_.~<".contains(chars[i])
                            && !(chars[i] == '/' && chars.get(i + 1) == Some(&'*'))
                        {
                            i += 1;
                        }
                        if i == start {
                            i += 1;
                        }
                        push(&mut spans, chars[start..i].iter().collect(), Style::default());
                    }
                }
            }
        }
        out.push(spans);
    }
    out
}
