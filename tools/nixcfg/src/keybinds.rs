//! Read the Hyprland keybinds of the Caelestia config, for the Keybinds tab.
//!
//! `hyprctl binds` is no help with Hyprland's Lua config: every bind's
//! dispatcher shows up as `__lua`. So the binds are read from the Lua files
//! themselves, without running them:
//!
//! - Caelestia's defaults: the `kb*` variables of ~/.config/hypr/variables.lua,
//!   bound by the `create_bind(vars.kbX, action, flags)` calls of
//!   ~/.config/hypr/hyprland/keybinds.lua (which also binds a few keys
//!   literally, like the brightness keys);
//! - the overrides of config/caelestia/hypr-vars.lua, applied on top (the way
//!   hyprland.lua merges them: a key replaces the default, "" removes the bind);
//! - the user's own `hl.bind(key, action, { description = ... })` calls of
//!   config/caelestia/hypr-user.lua.
//!
//! The parser is a small Lua tokenizer: strings ("", '', [[ ]]), comments
//! (-- and --[[ ]]) and nesting (brackets and function/do/then ... end) are
//! handled, anything else is kept as source text.

use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::LazyLock;

use regex::{NoExpand, Regex};

use crate::text::char_len;

/// Names of Caelestia's kb* variables. A variable missing here is named from
/// its own name (kbFooBar -> "Foo bar").
const LABELS: &[(&str, &str)] = &[
    ("kbGoToWs", "Go to workspace"),
    ("kbGoToWsGroup", "Go to workspace group"),
    ("kbMoveWinToWs", "Move window to workspace"),
    ("kbMoveWinToWsSilent", "Send window to workspace (stay)"),
    ("kbMoveWinToWsGroup", "Move window to workspace group"),
    ("kbMoveWinToWsSpecial", "Move window to the scratchpad"),
    ("kbMoveWinFromWsSpecial", "Move window out of the scratchpad"),
    ("kbMoveWinToWsNext", "Move window to the next workspace"),
    ("kbMoveWinToWsPrev", "Move window to the previous workspace"),
    ("kbNextWs", "Next workspace"),
    ("kbPrevWs", "Previous workspace"),
    ("kbNextWsGroup", "Next workspace group"),
    ("kbPrevWsGroup", "Previous workspace group"),
    ("kbWindowCycleNext", "Next window"),
    ("kbWindowCyclePrev", "Previous window"),
    ("kbWindowGroupCycleNext", "Next window in the group"),
    ("kbWindowGroupCyclePrev", "Previous window in the group"),
    ("kbUngroup", "Take the window out of its group"),
    ("kbToggleGroup", "Group / ungroup windows"),
    ("kbGroupLockActive", "Lock the window group"),
    ("kbWindowDecreaseWidth", "Narrower window"),
    ("kbWindowIncreaseWidth", "Wider window"),
    ("kbWindowDecreaseHeight", "Shorter window"),
    ("kbWindowIncreaseHeight", "Taller window"),
    ("kbMoveWindow", "Drag the window (hold)"),
    ("kbResizeWindow", "Resize the window (hold)"),
    ("kbCenterWindow", "Center the window"),
    ("kbNormalizeWindow", "Normal size, centered"),
    ("kbWindowPip", "Picture in picture"),
    ("kbPinWindow", "Pin the window (every workspace)"),
    ("kbWindowFullscreen", "Fullscreen"),
    ("kbWindowBorderedFullscreen", "Maximize"),
    ("kbToggleWindowFloating", "Float / tile the window"),
    ("kbCloseWindow", "Close the window"),
    ("kbSpecialWs", "Scratchpad"),
    ("kbSystemMonitorWs", "System monitor"),
    ("kbMusicWs", "Music"),
    ("kbCommunicationWs", "Communication (Discord...)"),
    ("kbTodoWs", "Todo"),
    ("kbTerminal", "Terminal"),
    ("kbBrowser", "Browser"),
    ("kbEditor", "Editor"),
    ("kbFileExplorer", "Files"),
    ("kbAudioSettings", "Audio settings"),
    ("kbScreenshot", "Screenshot"),
    ("kbScreenshotFreeze", "Screenshot a region (frozen)"),
    ("kbScreenshotRegion", "Screenshot a region"),
    ("kbRecord", "Record the screen"),
    ("kbRecordSound", "Record the screen with sound"),
    ("kbRecordRegion", "Record a region"),
    ("kbColorPicker", "Color picker"),
    ("kbMediaToggle", "Play / pause"),
    ("kbMediaNext", "Next track"),
    ("kbMediaPrev", "Previous track"),
    ("kbMediaStop", "Stop the media"),
    ("kbVolumeMute", "Mute"),
    ("kbLauncher", "App launcher"),
    ("kbSession", "Session menu"),
    ("kbShowSidebar", "Sidebar"),
    ("kbClearNotifs", "Clear notifications"),
    ("kbShowPanels", "Show all panels"),
    ("kbLock", "Lock the screen"),
    ("kbRestoreLock", "Restore the lock screen"),
    ("kbSleep", "Sleep"),
    ("kbClipboard", "Clipboard history"),
    ("kbClipboardDel", "Delete from the clipboard history"),
    ("kbClipboardPasteLatest", "Type the latest clipboard entry"),
    ("kbEmoji", "Emoji picker"),
];

/// Names of the binds keybinds.lua writes literally, without a variable. The
/// extra keys of a variable (`{ vars.kbMediaToggle, "XF86AudioPlay" }`) are
/// named after it instead.
const LITERAL_LABELS: &[(&str, &str)] = &[
    ("CTRL + SUPER + SHIFT + R", "Kill the shell"),
    ("CTRL + SUPER + ALT + R", "Restart the shell"),
    ("XF86MonBrightnessUp", "Brightness up"),
    ("XF86MonBrightnessDown", "Brightness down"),
    ("XF86AudioMicMute", "Mute the microphone"),
    ("XF86AudioRaiseVolume", "Volume up"),
    ("XF86AudioLowerVolume", "Volume down"),
    ("SUPER + ALT + F12", "Test notification"),
];
/// Binds made in a `for _, dir in ipairs({...})` loop, by action ({} is the loop value)
const LOOP_LABELS: &[(&str, &str)] = &[
    ("focus({ direction = dir })", "Focus the window {}"),
    ("window.move({ direction = dir })", "Move the window {}"),
];

/// Modifier names as Hyprland reads them, to compare combos
const MODIFIERS: &[(&str, &str)] = &[
    ("SHIFT", "SHIFT"),
    ("CAPS", "CAPS"),
    ("CTRL", "CTRL"),
    ("CONTROL", "CTRL"),
    ("ALT", "ALT"),
    ("MOD2", "MOD2"),
    ("MOD3", "MOD3"),
    ("SUPER", "SUPER"),
    ("WIN", "SUPER"),
    ("LOGO", "SUPER"),
    ("MOD4", "SUPER"),
    ("MOD5", "MOD5"),
];

/// The bind flags of hl.bind's options table
const FLAGS: &[&str] = &["locked", "release", "repeating", "mouse", "non_consuming", "long_press"];

/// Keys bound by the "modifier only" variables (kbGoToWs...): modifier + 1..9, 0
const WS_KEYS: &str = "1-9, 0";

fn lookup<'a>(table: &[(&str, &'a str)], key: &str) -> Option<&'a str> {
    table.iter().find(|(k, _)| *k == key).map(|(_, v)| *v)
}

fn label_of(var: &str) -> String {
    lookup(LABELS, var).map_or_else(|| humanize(var), str::to_string)
}

#[derive(Clone, Debug)]
pub struct Bind {
    pub combo: String, // as written, "SUPER + Q"; "" when the bind is removed
    pub label: String, // what it does, in words
    pub action: String, // the Lua action, shortened ("exec kitty", "caelestia:launcher")
    pub source: &'static str, // "default", "override" or "user"
    pub path: PathBuf, // the file to change it in
    pub line: usize, // its line in that file (1-based)
    pub var: String, // the kb* variable, for Caelestia's binds
    pub default: String, // an override: the default combo it replaces
    pub section: String, // Caelestia's comment heading in keybinds.lua, or "Your binds"
    pub flags: Vec<String>,
    pub conflict: bool, // another bind with a different action on the same combo
}

impl Bind {
    pub fn disabled(&self) -> bool {
        self.combo.is_empty()
    }
    pub fn release(&self) -> bool {
        self.flags.iter().any(|f| f == "release")
    }
}

// Tokenizer

#[derive(Clone, Copy, PartialEq, Debug)]
enum Kind {
    Str,
    Name,
    Num,
    Op,
}

#[derive(Clone, Debug)]
struct Token {
    kind: Kind,
    value: String, // a string's contents, or the token's text
    start: usize, // byte offsets in the source
    end: usize,
    line: usize, // 1-based
}

static LONG_BRACKET: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^\[(=*)\[").unwrap());
static NAME: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^[A-Za-z_]\w*").unwrap());
static NUMBER: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^(?:0[xX][0-9a-fA-F]+|\d+\.?\d*(?:[eE][+-]?\d+)?|\.\d+)").unwrap());
const OPERATORS: &[&str] = &["...", "..", "==", "~=", "<=", ">=", "//", "::", "<<", ">>"];

fn count_newlines(s: &str) -> usize {
    s.bytes().filter(|&b| b == b'\n').count()
}

/// The tokens of a Lua file, and its whole-line comments by line.
fn tokenize(text: &str) -> (Vec<Token>, HashMap<usize, String>) {
    let mut tokens = Vec::new();
    let mut comments = HashMap::new();
    let n = text.len();
    let (mut i, mut line) = (0, 1);
    let mut line_has_code = false;
    while i < n {
        let c = text[i..].chars().next().unwrap();
        if c == '\n' {
            line += 1;
            line_has_code = false;
            i += 1;
            continue;
        }
        if c.is_whitespace() {
            i += c.len_utf8();
            continue;
        }
        if text[i..].starts_with("--") {
            if let Some(long) = LONG_BRACKET.captures(&text[i + 2..]) {
                let open = long[0].len();
                let closing = format!("]{}]", &long[1]);
                let from = i + 2 + open;
                let close = text[from..].find(&closing).map_or(n, |p| from + p + open);
                line += count_newlines(&text[i..close]);
                i = close;
                continue;
            }
            let end = text[i..].find('\n').map_or(n, |p| i + p);
            if !line_has_code {
                comments.insert(line, text[i + 2..end].trim().to_string());
            }
            i = end;
            continue;
        }
        line_has_code = true;
        let (start, start_line) = (i, line);
        let long = if c == '[' { LONG_BRACKET.captures(&text[i..]) } else { None };
        if let Some(long) = long {
            let open = long[0].len();
            let closing = format!("]{}]", &long[1]);
            let from = i + open;
            let close = text[from..].find(&closing).map_or(n, |p| from + p);
            let value = text[from..close].strip_prefix('\n').unwrap_or(&text[from..close]).to_string();
            i = n.min(close + open);
            line += count_newlines(&text[start..i]);
            tokens.push(Token { kind: Kind::Str, value, start, end: i, line: start_line });
        } else if c == '"' || c == '\'' {
            i += 1;
            let mut chars = String::new();
            while i < n {
                let ch = text[i..].chars().next().unwrap();
                if ch == c {
                    break;
                }
                if ch == '\\' && i + 1 < n {
                    let next = text[i + 1..].chars().next().unwrap();
                    chars.push(match next {
                        'n' => '\n',
                        't' => '\t',
                        'r' => '\r',
                        other => other,
                    });
                    i += 1 + next.len_utf8();
                    continue;
                }
                if ch == '\n' {
                    break; // unfinished string
                }
                chars.push(ch);
                i += ch.len_utf8();
            }
            i += 1;
            let i_end = i.min(n);
            tokens.push(Token { kind: Kind::Str, value: chars, start, end: i_end, line: start_line });
        } else if let Some(m) = NAME.find(&text[i..]) {
            i += m.end();
            tokens.push(Token { kind: Kind::Name, value: m.as_str().into(), start, end: i, line: start_line });
        } else if let Some(m) = NUMBER.find(&text[i..]) {
            i += m.end();
            tokens.push(Token { kind: Kind::Num, value: m.as_str().into(), start, end: i, line: start_line });
        } else {
            let op = OPERATORS.iter().find(|o| text[i..].starts_with(**o)).map_or_else(|| c.to_string(), |o| o.to_string());
            i += op.len();
            tokens.push(Token { kind: Kind::Op, value: op, start, end: i, line: start_line });
        }
    }
    (tokens, comments)
}

/// +1 when a token opens a bracket or a block, -1 when it closes one.
fn nesting(t: &Token) -> i64 {
    let v = t.value.as_str();
    match t.kind {
        Kind::Op => matches!(v, "(" | "{" | "[") as i64 - matches!(v, ")" | "}" | "]") as i64,
        // "if ... then ... end" and "for/while ... do ... end": then and do open the block,
        // and "elseif ... then" closes the previous branch before its then opens the next one
        Kind::Name => {
            matches!(v, "function" | "do" | "then" | "repeat") as i64
                - matches!(v, "end" | "until") as i64
                - (v == "elseif") as i64
        }
        _ => 0,
    }
}

/// The comma-separated items after an opening bracket, and the index of its closing one.
fn split_args(tokens: &[Token], open_index: usize) -> (Vec<Vec<Token>>, usize) {
    let mut items: Vec<Vec<Token>> = vec![vec![]];
    let mut depth = 0;
    let mut i = open_index + 1;
    while i < tokens.len() {
        let t = &tokens[i];
        if depth == 0 && t.kind == Kind::Op {
            if matches!(t.value.as_str(), ")" | "}" | "]") {
                break;
            }
            if matches!(t.value.as_str(), "," | ";") {
                items.push(vec![]);
                i += 1;
                continue;
            }
        }
        depth += nesting(t);
        items.last_mut().unwrap().push(t.clone());
        i += 1;
    }
    (items.into_iter().filter(|it| !it.is_empty()).collect(), i)
}

/// The (line, arguments) of every call to a function, like "hl.bind".
fn calls(tokens: &[Token], name: &str) -> Vec<(usize, Vec<Vec<Token>>)> {
    let parts: Vec<&str> = name.split('.').collect();
    let mut pattern: Vec<&str> = parts.iter().flat_map(|p| [*p, "."]).collect();
    pattern.pop();
    let mut found = Vec::new();
    for i in 0..tokens.len().saturating_sub(pattern.len()) {
        if i > 0 {
            let prev = &tokens[i - 1];
            if prev.kind == Kind::Op && (prev.value == "." || prev.value == ":") {
                continue; // x.hl.bind or "function foo.create_bind" are not calls of it
            }
            if prev.kind == Kind::Name && prev.value == "function" {
                continue; // its definition
            }
        }
        if pattern.iter().enumerate().all(|(k, p)| tokens[i + k].value == *p) {
            let after = i + pattern.len();
            if after < tokens.len() && tokens[after].value == "(" {
                let (args, _) = split_args(tokens, after);
                found.push((tokens[i].line, args));
            }
        }
    }
    found
}

// Values

/// A Lua value as far as nixcfg cares: a plain string or a table of them.
#[derive(Clone, Debug, PartialEq)]
enum Lit {
    Str(String),
    List(Vec<String>),
    Other,
}

impl Lit {
    fn as_str(&self) -> Option<&str> {
        match self {
            Lit::Str(s) => Some(s),
            _ => None,
        }
    }
    /// `v if list else [v] if str else []`
    fn strings(&self) -> Vec<String> {
        match self {
            Lit::Str(s) => vec![s.clone()],
            Lit::List(l) => l.clone(),
            Lit::Other => vec![],
        }
    }
}

/// A plain string, or a table of plain strings (as a list); Other for anything else.
fn literal(item: &[Token]) -> Lit {
    if item.len() == 1 && item[0].kind == Kind::Str {
        return Lit::Str(item[0].value.clone());
    }
    if !item.is_empty() && item[0].value == "{" && item[item.len() - 1].value == "}" {
        let (values, _) = split_args(item, 0);
        let strings: Option<Vec<String>> = values
            .iter()
            .map(|v| match literal(v) {
                Lit::Str(s) => Some(s),
                _ => None,
            })
            .collect();
        if let Some(strings) = strings {
            return Lit::List(strings);
        }
    }
    Lit::Other
}

struct Field {
    value: Lit,
    line: usize,
    tokens: Vec<Token>,
}

/// The `name = value` fields of a table, in order (a repeated name keeps its first place).
fn table_fields(tokens: &[Token], open_index: usize) -> Vec<(String, Field)> {
    let mut fields: Vec<(String, Field)> = Vec::new();
    let (items, _) = split_args(tokens, open_index);
    for item in items {
        if item.len() >= 3 && item[0].kind == Kind::Name && item[1].value == "=" {
            let field = Field { value: literal(&item[2..]), line: item[0].line, tokens: item[2..].to_vec() };
            match fields.iter_mut().find(|(k, _)| *k == item[0].value) {
                Some((_, f)) => *f = field,
                None => fields.push((item[0].value.clone(), field)),
            }
        }
    }
    fields
}

type Vars = Vec<(String, (Lit, usize))>;

fn var_get<'a>(vars: &'a Vars, name: &str) -> Option<&'a (Lit, usize)> {
    vars.iter().find(|(k, _)| k == name).map(|(_, v)| v)
}

/// The fields of the table a variables file returns: name -> (value, line).
///
/// Values that are not plain strings (numbers, "a" .. b) are Other.
fn read_vars(path: &Path) -> Vars {
    let Ok(text) = std::fs::read_to_string(path) else { return vec![] };
    let (tokens, _) = tokenize(&text);
    for i in 0..tokens.len().saturating_sub(1) {
        if tokens[i].kind == Kind::Name && tokens[i].value == "return" && tokens[i + 1].value == "{" {
            return table_fields(&tokens, i + 1).into_iter().map(|(k, f)| (k, (f.value, f.line))).collect();
        }
    }
    vec![]
}

fn source_text(text: &str, item: &[Token]) -> String {
    match (item.first(), item.last()) {
        (Some(a), Some(b)) => text[a.start..b.end].split_whitespace().collect::<Vec<_>>().join(" "),
        _ => String::new(),
    }
}

/// "kbX" for `vars.kbX`.
fn var_ref(item: &[Token]) -> Option<String> {
    (item.len() == 3 && item[0].value == "vars" && item[1].value == "." && item[2].kind == Kind::Name)
        .then(|| item[2].value.clone())
}

fn shorten(text: &str) -> String {
    const WIDTH: usize = 60;
    if char_len(text) <= WIDTH {
        text.to_string()
    } else {
        text.chars().take(WIDTH - 1).collect::<String>() + "…"
    }
}

static EXEC: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"^hl\.dsp\.exec_cmd\((.*)\)$").unwrap());
static GLOBAL: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"^hl\.dsp\.global\("([^"]*)"\)$"#).unwrap());
static TOGGLE: LazyLock<Regex> = LazyLock::new(|| Regex::new(r#"^fn\.toggle\("([^"]*)"\)$"#).unwrap());
static WSACTION: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"^fn\.wsaction\("(\w+)", "(\w*)", \w+\)$"#).unwrap());

/// A short name for a bind's Lua action.
fn describe_action(text: &str, item: &[Token], resolve: &dyn Fn(&str) -> Lit) -> String {
    if item.is_empty() {
        return String::new();
    }
    if item[0].value == "function" {
        let commands: Vec<&str> = (2..item.len())
            .filter(|&k| item[k].kind == Kind::Str && item[k - 2].value == "exec_cmd")
            .map(|k| item[k].value.as_str())
            .collect();
        if !commands.is_empty() {
            return shorten(&format!("lua: {}", commands.join(" / ")));
        }
        return "lua function".into();
    }
    let source = source_text(text, item);
    if let Some(m) = EXEC.captures(&source) {
        let open = item.iter().position(|t| t.value == "(").unwrap_or(0);
        let (args, _) = split_args(item, open);
        let mut command = args.first().map_or(Lit::Other, |a| literal(a));
        if command == Lit::Other
            && let Some(var) = args.first().and_then(|a| var_ref(a))
        {
            command = resolve(&var);
        }
        return shorten(&format!("exec {}", command.as_str().unwrap_or(m[1].trim())));
    }
    if let Some(m) = GLOBAL.captures(&source) {
        return m[1].to_string();
    }
    if let Some(m) = TOGGLE.captures(&source) {
        return format!("toggle special:{}", &m[1]);
    }
    if let Some(m) = WSACTION.captures(&source) {
        return format!("{} {} n", &m[1], if m[2].is_empty() { "workspace" } else { "group" });
    }
    shorten(source.strip_prefix("hl.dsp.").unwrap_or(&source))
}

fn humanize(var: &str) -> String {
    let name = var.strip_prefix("kb").unwrap_or(var);
    let mut words = String::new();
    for (i, c) in name.chars().enumerate() {
        if i > 0 && c.is_ascii_uppercase() {
            words.push(' ');
        }
        words.push(c);
    }
    let words = words.to_lowercase();
    let mut chars = words.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().chain(chars).collect(),
        None => String::new(),
    }
}

/// Two combos Hyprland treats the same give the same key.
pub fn combo_key(combo: &str) -> (Vec<String>, String) {
    let mut mods = BTreeSet::new();
    let mut key = String::new();
    for part in combo.split('+').map(str::trim) {
        if let Some(m) = lookup(MODIFIERS, &part.to_uppercase()) {
            mods.insert(m.to_string());
        } else if !part.is_empty() {
            key = part.to_lowercase();
        }
    }
    (mods.into_iter().collect(), key)
}

/// `local locked = { locked = true }` -> {"locked": ["locked"]}.
fn flag_tables(tokens: &[Token]) -> HashMap<String, Vec<String>> {
    let mut tables = HashMap::new();
    for i in 0..tokens.len().saturating_sub(3) {
        if tokens[i].value == "local"
            && tokens[i + 1].kind == Kind::Name
            && tokens[i + 2].value == "="
            && tokens[i + 3].value == "{"
        {
            let fields = table_fields(tokens, i + 3);
            if !fields.is_empty() && fields.iter().all(|(_, f)| f.tokens.len() == 1 && f.tokens[0].value == "true") {
                let flags = fields.into_iter().map(|(k, _)| k).filter(|k| FLAGS.contains(&k.as_str())).collect();
                tables.insert(tokens[i + 1].value.clone(), flags);
            }
        }
    }
    tables
}

/// `for _, dir in ipairs({ "left", "right" }) do` -> {"dir": ["left", "right"]}.
fn loop_values(tokens: &[Token]) -> HashMap<String, Vec<String>> {
    let mut loops = HashMap::new();
    for i in 0..tokens.len().saturating_sub(6) {
        if tokens[i].value == "for"
            && tokens[i + 3].kind == Kind::Name
            && tokens[i + 4].value == "in"
            && tokens[i + 5].value == "ipairs"
            && tokens[i + 6].value == "("
        {
            let (args, _) = split_args(tokens, i + 6);
            if let Some(Lit::List(values)) = args.first().map(|a| literal(a)) {
                loops.insert(tokens[i + 3].value.clone(), values);
            }
        }
    }
    loops
}

/// The nearest short heading comment above a line ("-- Window actions").
fn section_of(comments: &HashMap<usize, String>, line: usize) -> String {
    for n in (1..line).rev() {
        if let Some(c) = comments.get(&n)
            && !c.is_empty()
            && char_len(c) <= 40
            && !c.ends_with(['.', ':'])
        {
            return c.clone();
        }
    }
    String::new()
}

// Binds

struct Caelestia<'a> {
    defaults: &'a Vars,
    overrides: &'a Vars,
    vars_path: &'a Path,
    binds_path: &'a Path,
    user_vars: &'a Path,
    loops: HashMap<String, Vec<String>>,
    binds: Vec<Bind>,
    used: HashSet<String>,
}

/// One create_bind call being read.
struct Call {
    line: usize,
    section: String,
    flags: Vec<String>,
    what: String,
}

impl Caelestia<'_> {
    fn default_of(&self, var: &str) -> Lit {
        var_get(self.defaults, var).map_or(Lit::Other, |v| v.0.clone())
    }

    fn add(&mut self, call: &Call, combo: &str, label: String, var: &str, ws: bool, action: Option<String>) {
        let what = action.unwrap_or_else(|| call.what.clone());
        if !var.is_empty()
            && let Some((new, new_line)) = var_get(self.overrides, var).cloned()
        {
            let olds = self.default_of(var).strings();
            let news: Vec<String> = new.strings().into_iter().filter(|c| !c.trim().is_empty()).collect();
            if combo != olds.first().map_or("", |s| s.as_str()) {
                return; // the override's combos are all added with the first default one
            }
            let default = olds
                .iter()
                .map(|o| if ws { format!("{o} + {WS_KEYS}") } else { o.clone() })
                .collect::<Vec<_>>()
                .join(" · ");
            let news = if news.is_empty() { vec![String::new()] } else { news };
            for c in news {
                self.binds.push(Bind {
                    combo: if ws && !c.is_empty() { format!("{c} + {WS_KEYS}") } else { c },
                    label: label.clone(),
                    action: what.clone(),
                    source: "override",
                    path: self.user_vars.to_path_buf(),
                    line: new_line,
                    var: var.into(),
                    default: default.clone(),
                    section: call.section.clone(),
                    flags: call.flags.clone(),
                    conflict: false,
                });
            }
            return;
        }
        let (path, at) = match var_get(self.defaults, var) {
            Some((_, line)) => (self.vars_path, *line),
            None => (self.binds_path, call.line),
        };
        self.binds.push(Bind {
            combo: if ws { format!("{combo} + {WS_KEYS}") } else { combo.into() },
            label,
            action: what,
            source: "default",
            path: path.to_path_buf(),
            line: at,
            var: var.into(),
            default: String::new(),
            section: call.section.clone(),
            flags: call.flags.clone(),
            conflict: false,
        });
    }

    fn add_key(&mut self, call: &Call, item: &[Token], sibling: &str) {
        let label_or = |plain: &str| -> String {
            if !sibling.is_empty() {
                sibling.to_string()
            } else {
                lookup(LITERAL_LABELS, plain).map_or_else(|| call.what.clone(), str::to_string)
            }
        };
        if let Some(var) = var_ref(item) {
            self.used.insert(var.clone());
            let mut combos: Vec<String> =
                self.default_of(&var).strings().into_iter().filter(|c| !c.trim().is_empty()).collect();
            if var_get(self.overrides, &var).is_some() && combos.is_empty() {
                combos = vec![String::new()]; // a variable with no default, set in hypr-vars.lua
            }
            for combo in combos {
                self.add(call, &combo, label_of(&var), &var, false, None);
            }
            return;
        }
        match literal(item) {
            Lit::Str(plain) => {
                let label = label_or(&plain);
                self.add(call, &plain, label, "", false, None);
            }
            Lit::List(list) => {
                for c in list {
                    let label = label_or(&c);
                    self.add(call, &c, label, "", false, None);
                }
            }
            Lit::Other if !item.is_empty() && item[0].value == "{" => {
                let (subs, _) = split_args(item, 0);
                // literal keys next to a variable do the same thing: named after it
                let named = subs.iter().find_map(|s| var_ref(s));
                let sibling = named.map_or(String::new(), |n| label_of(&n));
                for sub in subs {
                    self.add_key(call, &sub, &sibling);
                }
            }
            Lit::Other if item.len() >= 4 && item[0].value == "extend_keybind" && item[1].value == "(" => {
                let (inner, _) = split_args(item, 1);
                if let Some(var) = inner.first().and_then(|i| var_ref(i)) {
                    self.used.insert(var.clone());
                    let m = self.default_of(&var);
                    let has_default = m.as_str().is_some_and(|s| !s.trim().is_empty());
                    if has_default || var_get(self.overrides, &var).is_some() {
                        let combo = m.as_str().unwrap_or("").to_string();
                        self.add(call, &combo, label_of(&var), &var, true, None);
                    }
                }
            }
            Lit::Other
                if item.len() == 3
                    && item[0].kind == Kind::Str
                    && item[1].value == ".."
                    && self.loops.contains_key(&item[2].value) =>
            {
                let loop_var = &item[2].value;
                let word = Regex::new(&format!(r"\b{}\b", regex::escape(loop_var))).unwrap();
                for v in self.loops[loop_var].clone() {
                    let label = match lookup(LOOP_LABELS, &call.what) {
                        Some(t) => t.replace("{}", &v),
                        None => format!("{} {v}", call.what),
                    };
                    let action = word.replace_all(&call.what, NoExpand(&format!("\"{v}\""))).into_owned();
                    self.add(call, &format!("{}{v}", item[0].value), label, "", false, Some(action));
                }
            }
            Lit::Other => {}
        }
    }
}

/// Caelestia's binds, in keybinds.lua's order, with the overrides applied.
fn caelestia_binds(defaults: &Vars, overrides: &Vars, vars_path: &Path, binds_path: &Path, user_vars: &Path) -> Vec<Bind> {
    let Ok(text) = std::fs::read_to_string(binds_path) else { return vec![] };
    let (tokens, comments) = tokenize(&text);
    let flags_by_name = flag_tables(&tokens);
    let mut c = Caelestia {
        defaults,
        overrides,
        vars_path,
        binds_path,
        user_vars,
        loops: loop_values(&tokens),
        binds: vec![],
        used: HashSet::new(),
    };
    let value = |name: &str| -> Lit {
        var_get(overrides, name).or(var_get(defaults, name)).map_or(Lit::Other, |v| v.0.clone())
    };
    for (line, args) in calls(&tokens, "create_bind") {
        if args.len() < 2 {
            continue;
        }
        let flags = match args.get(2) {
            Some(a) if a.len() == 1 => flags_by_name.get(&a[0].value).cloned().unwrap_or_default(),
            _ => vec![],
        };
        let call = Call { line, section: section_of(&comments, line), flags, what: describe_action(&text, &args[1], &value) };
        c.add_key(&call, &args[0], "");
    }

    // Overrides of variables keybinds.lua does not use (a typo, or a removed bind)
    for (var, (new, line)) in overrides {
        if var.starts_with("kb") && !c.used.contains(var) {
            let combos = match new {
                Lit::Other => vec![String::new()],
                other => other.strings(),
            };
            for combo in combos {
                c.binds.push(Bind {
                    combo,
                    label: format!("{} (not used by Caelestia)", humanize(var)),
                    action: String::new(),
                    source: "override",
                    path: user_vars.to_path_buf(),
                    line: *line,
                    var: var.clone(),
                    default: String::new(),
                    section: "Unknown variables".into(),
                    flags: vec![],
                    conflict: false,
                });
            }
        }
    }
    c.binds
}

/// The hl.bind calls of hypr-user.lua.
fn user_binds(path: &Path) -> Vec<Bind> {
    let Ok(text) = std::fs::read_to_string(path) else { return vec![] };
    let (tokens, _) = tokenize(&text);
    let mut binds: Vec<Bind> = Vec::new();
    for (line, args) in calls(&tokens, "hl.bind") {
        if args.len() < 2 {
            continue;
        }
        let combo = match literal(&args[0]) {
            Lit::Str(s) => s,
            _ => source_text(&text, &args[0]),
        };
        let what = describe_action(&text, &args[1], &|_| Lit::Other);
        let (mut label, mut flags) = (String::new(), Vec::new());
        if let Some(opts) = args.get(2)
            && !opts.is_empty()
            && opts[0].value == "{"
        {
            let options = table_fields(opts, 0);
            if let Some((_, f)) = options.iter().find(|(k, _)| k == "description")
                && let Lit::Str(d) = &f.value
            {
                label = d.clone();
            }
            flags = options
                .iter()
                .filter(|(k, f)| FLAGS.contains(&k.as_str()) && source_text(&text, &f.tokens) == "true")
                .map(|(k, _)| k.clone())
                .collect();
        }
        if label.is_empty() && flags.iter().any(|f| f == "release") {
            // the release half of a press / release pair (F8 for Nova)
            let key = combo_key(&combo);
            if let Some(pressed) = binds.iter().rev().find(|b| combo_key(&b.combo) == key) {
                label = format!("{} (released)", pressed.label);
            }
        }
        binds.push(Bind {
            combo,
            label: if label.is_empty() { what.clone() } else { label },
            action: what,
            source: "user",
            path: path.to_path_buf(),
            line,
            var: String::new(),
            default: String::new(),
            section: "Your binds".into(),
            flags,
            conflict: false,
        });
    }
    binds
}

/// Caelestia's files (installed by the caelestia module, not in the dotfiles)
pub fn hypr_dir() -> PathBuf {
    crate::cfg::home().join(".config/hypr")
}

/// Every bind: Caelestia's (with the overrides), then the user's.
pub fn load(dotfiles: &Path) -> Vec<Bind> {
    let hypr = hypr_dir();
    let (default_vars, default_binds) = (hypr.join("variables.lua"), hypr.join("hyprland/keybinds.lua"));
    let user_vars = dotfiles.join("config/caelestia/hypr-vars.lua");
    let defaults = read_vars(&default_vars);
    let overrides = read_vars(&user_vars);
    let mut binds = caelestia_binds(&defaults, &overrides, &default_vars, &default_binds, &user_vars);
    binds.extend(user_binds(&dotfiles.join("config/caelestia/hypr-user.lua")));

    // The same combo bound twice to the same action is harmless (Caelestia binds
    // SUPER + mouse:273 both literally and as kbResizeWindow): shown once
    let mut seen = HashSet::new();
    let mut unique: Vec<Bind> = Vec::new();
    for b in binds {
        if b.disabled() || seen.insert((combo_key(&b.combo), b.action.clone(), b.release())) {
            unique.push(b);
        }
    }

    // Several actions on one combo all run on the same key press
    let mut actions: BTreeMap<((Vec<String>, String), bool), HashSet<String>> = BTreeMap::new();
    for b in unique.iter().filter(|b| !b.disabled()) {
        actions.entry((combo_key(&b.combo), b.release())).or_default().insert(b.action.clone());
    }
    for b in &mut unique {
        b.conflict = !b.disabled() && actions[&(combo_key(&b.combo), b.release())].len() > 1;
    }
    unique
}
