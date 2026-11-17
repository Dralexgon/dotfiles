//! The TUI: three tabs (Modules, Packages, Keybinds), modal dialogs and
//! notifications, ported from the Textual version (legacy/nixcfg.py) with the
//! same keys, layout and behavior.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::mpsc::{Receiver, Sender, channel};
use std::time::{Duration, Instant};

use crossterm::event::{
    self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseButton,
    MouseEvent, MouseEventKind,
};
use crossterm::execute;
use crossterm::terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode};
use ratatui::Frame;
use ratatui::Terminal;
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Position, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, Clear, Paragraph, Wrap};
use unicode_width::UnicodeWidthStr;

use crate::cfg::{self, CORE, DESKTOP_CORE, DOTFILES, MODULE_NAME, MODULE_TEMPLATE, SYSTEM_PROFILE};
use crate::keybinds::{self, Bind};
use crate::text::{pad, posix};
use crate::theme::{self, Theme};
use crate::widgets::{Input, List, Row, Spans, dim_spans, plain, span, spans_width, wrapped_height};
use crate::{hostfile, modfile, nixhl, tray, window};

/// Below this width, the file preview column is hidden.
const PREVIEW_MIN_WIDTH: u16 = 120;

/// A nix search result: attribute path, version, description.
pub type SearchResult = (String, String, String);

pub enum Msg {
    Quit,
    Checked { id: u64, name: String, text: String, error: Option<String> },
    Searched { id: u64, found: Vec<SearchResult>, total: usize, error: String },
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum Tab {
    Modules,
    Packages,
    Keybinds,
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum Focus {
    Modules,
    ModulePackages,
    Filter,
    AllPackages,
    KbFilter,
    Keybinds,
}

#[derive(Clone, Copy, PartialEq)]
enum Severity {
    Info,
    Warning,
    Error,
}

struct Toast {
    title: String,
    message: String,
    severity: Severity,
    until: Instant,
}

#[derive(Clone, Copy, PartialEq, Debug)]
enum Action {
    Tab(Tab),
    SwitchHost,
    NewModule,
    Edit,
    DeleteModule,
    DefaultDesktop,
    AddPackage,
    RemovePackage,
    FocusFilter,
    GitDiff,
    Update,
    Build,
    Rebuild,
    Generations,
    ToggleTheme,
    Quit,
    Hide,
}

/// The app's key bindings, in footer order.
const BINDINGS: &[(&str, &str, Action)] = &[
    ("1", "Modules", Action::Tab(Tab::Modules)),
    ("2", "Packages", Action::Tab(Tab::Packages)),
    ("3", "Keybinds", Action::Tab(Tab::Keybinds)),
    ("h", "Host", Action::SwitchHost),
    ("n", "New module", Action::NewModule),
    ("e", "Edit", Action::Edit),
    ("D", "Delete module", Action::DeleteModule),
    ("s", "Default desktop", Action::DefaultDesktop),
    ("a", "Add package", Action::AddPackage),
    ("x", "Remove package", Action::RemovePackage),
    ("/", "Filter", Action::FocusFilter),
    ("g", "Diff", Action::GitDiff),
    ("u", "Update", Action::Update),
    ("b", "Build", Action::Build),
    ("r", "Switch", Action::Rebuild),
    ("c", "Generations", Action::Generations),
    ("t", "Theme", Action::ToggleTheme),
    ("q", "Quit", Action::Quit),
    ("esc", "Hide", Action::Hide),
];

#[derive(Clone)]
enum AddTarget {
    Module(String),
    Host,
}

enum PromptFor {
    NewModule,
    Description { target: AddTarget, attr: String },
}

enum ConfirmFor {
    DeleteModule(String),
    Run { cmd: Vec<String>, what: &'static str },
}

enum Modal {
    Prompt { title: String, input: Input, allow_empty: bool, purpose: PromptFor },
    Confirm { question: Vec<Spans>, purpose: ConfirmFor },
    Choose { title: String, list: List },
    Generations { list: List, selected: HashSet<u32> },
    Search { target: AddTarget, title: String, input: Input, status: Spans, list: List, on_results: bool, id: u64 },
}

pub struct App {
    host: String,
    hostname: String,
    state: Vec<String>, // the modules the host turns on (see cfg::load_state)
    expanded: HashSet<String>, // groups shown open in the module list
    module: Option<String>, // module shown in the packages column
    entries: Vec<modfile::Entry>, // its packages
    good: HashMap<PathBuf, String>, // last module text that passed the check
    check_status: Option<Spans>,
    check_id: u64,
    search_id: u64,
    tab: Tab,
    focus: Focus,
    modules: List,
    packages: List,
    all_packages: List,
    keybinds: List,
    filter: Input,
    kb_filter: Input,
    hypr_binds: Vec<Bind>, // the Keybinds tab's rows
    preview: Vec<Spans>,
    preview_line: Option<usize>,
    preview_scroll: usize,
    preview_area: Rect,
    tab_labels: [Spans; 3],
    tab_areas: Vec<(Rect, Tab)>,
    footer_areas: Vec<(Rect, Action)>,
    theme: Theme,
    terminal_theme: bool, // t: the terminal's colors instead of nixcfg's
    scheme_mtime: Option<Option<std::time::SystemTime>>,
    theme_checked: Instant,
    modal: Option<Modal>,
    toasts: Vec<Toast>,
    tray: Option<tray::TrayHandle>,
    tx: Sender<Msg>,
    rx: Receiver<Msg>,
    quit: bool,
    needs_clear: bool,
    width: u16,
}

type Term = Terminal<CrosstermBackend<io::Stdout>>;

fn enter_tui() -> io::Result<()> {
    enable_raw_mode()?;
    execute!(io::stdout(), EnterAlternateScreen, EnableMouseCapture)
}

fn leave_tui() -> io::Result<()> {
    execute!(io::stdout(), DisableMouseCapture, LeaveAlternateScreen, crossterm::cursor::Show)?;
    disable_raw_mode()
}

pub fn run() -> io::Result<()> {
    enter_tui()?;
    // Put the terminal back even on a panic.
    let hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let _ = leave_tui();
        hook(info);
    }));
    let mut term = Terminal::new(CrosstermBackend::new(io::stdout()))?;
    let mut app = App::new();
    let result = app.main_loop(&mut term);
    leave_tui()?;
    result
}

impl App {
    fn new() -> Self {
        let hosts = cfg::list_hosts();
        let hostname = cfg::hostname();
        let host = if hosts.contains(&hostname) { hostname.clone() } else { hosts[0].clone() };
        let (tx, rx) = channel();
        let mut app = App {
            state: cfg::load_state(&host),
            host,
            hostname,
            expanded: HashSet::new(),
            module: None,
            entries: vec![],
            good: HashMap::new(),
            check_status: None,
            check_id: 0,
            search_id: 0,
            tab: Tab::Modules,
            focus: Focus::Modules,
            modules: List::default(),
            packages: List::default(),
            all_packages: List::default(),
            keybinds: List::default(),
            filter: Input::new("Filter all packages (press /)"),
            kb_filter: Input::new("Filter by key, name, action or source (press /)"),
            hypr_binds: vec![],
            preview: vec![],
            preview_line: None,
            preview_scroll: 0,
            preview_area: Rect::default(),
            tab_labels: Default::default(),
            tab_areas: vec![],
            footer_areas: vec![],
            theme: Theme::fallback(),
            terminal_theme: false,
            scheme_mtime: None,
            theme_checked: Instant::now(),
            modal: None,
            toasts: vec![],
            tray: None,
            tx,
            rx,
            quit: false,
            needs_clear: false,
            width: 0,
        };
        app.load_theme();
        app.refresh_all();
        app.modules.highlighted = (!app.modules.rows.is_empty()).then_some(0);
        app.module_highlighted();
        if window::in_session() {
            app.tray = tray::TrayHandle::start(app.tx.clone());
        }
        app
    }

    fn main_loop(&mut self, term: &mut Term) -> io::Result<()> {
        let mut dirty = true;
        while !self.quit {
            if self.needs_clear {
                term.clear()?;
                self.needs_clear = false;
                dirty = true;
            }
            if dirty {
                term.draw(|f| self.render(f))?;
                dirty = false;
            }
            if event::poll(Duration::from_millis(250))? {
                loop {
                    match event::read()? {
                        Event::Key(key) if key.kind != KeyEventKind::Release => self.on_key(key),
                        Event::Mouse(mouse) => self.on_mouse(mouse),
                        _ => {}
                    }
                    if self.quit || !event::poll(Duration::ZERO)? {
                        break;
                    }
                }
                dirty = true;
            }
            while let Ok(msg) = self.rx.try_recv() {
                self.on_msg(msg);
                dirty = true;
            }
            let now = Instant::now();
            let before = self.toasts.len();
            self.toasts.retain(|t| t.until > now);
            dirty |= self.toasts.len() != before;
            // Follow Caelestia when the wallpaper (and so the palette) changes.
            if now.duration_since(self.theme_checked) >= Duration::from_secs(2) {
                self.theme_checked = now;
                dirty |= self.load_theme();
            }
        }
        Ok(())
    }

    /// Leave the TUI to run something attached to the terminal.
    fn suspend<R>(&mut self, f: impl FnOnce() -> R) -> R {
        let _ = leave_tui();
        let result = f();
        let _ = enter_tui();
        self.needs_clear = true;
        result
    }

    fn notify(&mut self, message: impl Into<String>) {
        self.toast("", message, Severity::Info, 5);
    }

    fn toast(&mut self, title: &str, message: impl Into<String>, severity: Severity, secs: u64) {
        self.toasts.push(Toast {
            title: title.into(),
            message: message.into(),
            severity,
            until: Instant::now() + Duration::from_secs(secs),
        });
    }

    fn run_command(&mut self, cmd: Vec<String>, what: &str) {
        if let Some(tray) = &self.tray {
            let mut label = what.to_string();
            label[..1].make_ascii_uppercase();
            tray.set_busy(&format!("{label} running…"));
        }
        let theme = (!self.terminal_theme).then(|| self.theme.clone());
        self.suspend(|| run_in_terminal(&cmd, what, theme.as_ref()));
        if let Some(tray) = &self.tray {
            tray.set_busy("");
        }
    }

    // Display

    /// Load the theme when Caelestia's scheme changed; returns whether it did.
    fn load_theme(&mut self) -> bool {
        let mtime = theme::scheme_mtime();
        if self.scheme_mtime == Some(mtime) {
            return false;
        }
        self.scheme_mtime = Some(mtime);
        self.theme = Theme::load(self.terminal_theme);
        true
    }

    fn toggle_theme(&mut self) {
        self.terminal_theme = !self.terminal_theme;
        self.scheme_mtime = None; // makes load_theme apply it now
        self.load_theme();
        self.notify(if self.terminal_theme { "Terminal colors" } else { "nixcfg colors" });
    }

    fn refresh_all(&mut self) {
        self.refresh_modules();
        self.refresh_all_packages();
        self.refresh_keybinds();
    }

    fn module_names(&self) -> Vec<String> {
        cfg::module_names(&self.host, &self.state)
    }

    fn highlighted_module(&self) -> Option<String> {
        self.modules.current_id().map(str::to_string)
    }

    fn highlighted_line(&self) -> Option<usize> {
        self.packages.current_id().and_then(|id| id.parse().ok())
    }

    fn refresh_modules(&mut self) {
        let others: Vec<(String, Vec<String>)> =
            cfg::list_hosts().into_iter().filter(|h| *h != self.host).map(|h| (h.clone(), cfg::load_state(&h))).collect();
        let enabled = self.state.clone();
        let on_disk: HashSet<String> = cfg::list_modules().into_iter().collect();
        let names = self.module_names();
        let cores: Vec<Option<String>> = names.iter().map(|n| cfg::group_core(n)).collect();
        let visible: Vec<(String, Option<String>)> = names
            .iter()
            .zip(&cores)
            .filter(|(_, core)| core.as_ref().is_none_or(|c| self.expanded.contains(c)))
            .map(|(n, c)| (n.clone(), c.clone()))
            .collect();
        let default = hostfile::default_session(&cfg::read(&cfg::host_path(&self.host)));
        let t = self.theme.clone();
        let dim = t.dim();

        let current = self.highlighted_module();
        let previous = self.modules.highlighted;
        let mut rows = Vec::new();
        for (i, (name, core)) in visible.iter().enumerate() {
            let mut label: Spans;
            if let Some(core) = core {
                // Submodule: drawn as a branch of its group, dimmed when the group is off.
                let last = i + 1 == visible.len() || visible[i + 1].1.as_ref() != Some(core);
                let base = name.rsplit_once('/').map_or(name.as_str(), |(_, b)| b);
                label = vec![plain("  "), span(if last { "└─" } else { "├─" }, dim), plain(format!(" {base}"))];
                if core == DESKTOP_CORE && enabled.contains(name) && default.as_deref() == Some(cfg::desktop_name(name)) {
                    label.push(plain("  "));
                    label.push(span("★ login default", t.fg_of(t.primary)));
                }
                if !cfg::is_active(core, &enabled) {
                    label = dim_spans(&t, label);
                }
            } else if cfg::is_group(name) {
                let subs: Vec<&String> = names.iter().zip(&cores).filter(|(_, c)| c.as_deref() == Some(name)).map(|(n, _)| n).collect();
                let on = subs.iter().filter(|n| enabled.contains(n)).count();
                let arrow = if self.expanded.contains(name) { "▾" } else { "▸" };
                label = vec![plain(cfg::group_label(name).to_string()), plain("  "), span(format!("{on}/{} {arrow}", subs.len()), dim)];
            } else {
                label = vec![plain(name.clone())];
            }
            if name == CORE {
                rows.push(Row::selection(name, vec![plain(name.clone()), plain("  "), span("nixos/core.nix · every host", dim)], true));
                continue;
            }
            if name == DESKTOP_CORE {
                label.push(plain("  "));
                label.push(span("login screen, per host · s: default", dim));
                rows.push(Row::selection(name, label, true));
                continue;
            }
            if cfg::is_host_module(name) {
                let rel = crate::text::relative(&cfg::module_path(name), &DOTFILES).unwrap_or_default();
                rows.push(Row::selection(name, vec![plain("configuration  "), span(format!("{rel} · this host"), dim)], true));
                continue;
            }
            if !on_disk.contains(name) {
                label.push(plain("  "));
                label.push(span("missing file", t.fg_of(t.error)));
            }
            let used_by: Vec<&str> =
                others.iter().filter(|(_, mods)| cfg::is_active(name, mods)).map(|(h, _)| h.as_str()).collect();
            if !used_by.is_empty() {
                label.push(plain("  "));
                label.push(span(used_by.join(" · "), dim));
            }
            rows.push(Row::selection(name, label, enabled.contains(name)));
        }
        self.modules.set_rows(rows);
        let found = current.as_deref().is_some_and(|c| self.modules.select_id(c));
        if !found {
            let core = current.as_deref().and_then(cfg::group_core);
            if !core.is_some_and(|c| self.modules.select_id(&c))
                && let Some(p) = previous
                && !self.modules.rows.is_empty()
            {
                self.modules.highlighted = Some(p.min(self.modules.len() - 1));
            }
        }
        self.module_highlighted();

        let count = names.iter().filter(|n| cfg::is_active(n, &enabled)).count();
        self.tab_labels[0] = vec![plain("Modules "), span(format!("{count}/{}", names.len()), dim)];
    }

    /// The highlighted module changed (maybe): show its packages.
    fn module_highlighted(&mut self) {
        let name = self.highlighted_module();
        if name.is_some() && name != self.module {
            self.show_module(name, Some(None));
        }
    }

    /// Fill the packages and preview columns for a module. `line`: None keeps
    /// the highlighted package, Some(None) highlights none.
    fn show_module(&mut self, name: Option<String>, line: Option<Option<usize>>) {
        let current = match line {
            None => self.highlighted_line(),
            Some(line) => line,
        };
        self.module = name.clone();
        self.entries.clear();
        self.packages.set_rows(vec![]);
        let Some(name) = name.filter(|n| cfg::module_path(n).exists()) else {
            self.preview.clear();
            self.preview_line = None;
            return;
        };
        let t = self.theme.clone();
        let mut rows = Vec::new();
        for entry in cfg::module_entries(&name) {
            let label = if entry.editable {
                let mut l = vec![plain(entry.name.clone())];
                if !entry.comment.is_empty() {
                    l.push(plain("  "));
                    l.push(span(entry.comment.clone(), t.dim()));
                }
                l
            } else {
                vec![span(entry.name.clone(), t.dim().add_modifier(Modifier::ITALIC))]
            };
            rows.push(Row::selection(entry.line.to_string(), label, entry.enabled).disabled(!entry.editable));
            self.entries.push(entry);
        }
        self.packages.set_rows(rows);
        let shown = current.filter(|l| self.packages.select_id(&l.to_string()));
        self.show_preview(shown);
    }

    fn package_title(&self) -> Spans {
        let t = &self.theme;
        let Some(module) = &self.module else { return vec![] };
        let path = cfg::module_path(module);
        if !path.exists() {
            return vec![span("no file", t.dim())];
        }
        let on = self.entries.iter().filter(|e| e.enabled).count();
        let name = path.file_name().unwrap_or_default().to_string_lossy().into_owned();
        let mut title = vec![
            span(name, Style::default().add_modifier(Modifier::BOLD)),
            plain("  "),
            span(format!("{on}/{}", self.entries.len()), t.dim()),
        ];
        if let Some(status) = &self.check_status {
            title.push(plain("  "));
            title.extend(status.clone());
        }
        title
    }

    fn show_preview(&mut self, line: Option<usize>) {
        let Some(module) = &self.module else { return };
        let path = cfg::module_path(module);
        let Ok(text) = fs::read_to_string(&path) else { return };
        self.preview = nixhl::highlight(&text);
        self.preview_line = line;
        let half = self.preview_area.height as usize / 2;
        self.preview_scroll = line.map_or(0, |l| l.saturating_sub(half));
    }

    /// The flat list of every package: this host's and every module's.
    fn refresh_all_packages(&mut self) {
        let enabled = self.state.clone();
        let query = self.filter.value.trim().to_lowercase();
        let mut rows: Vec<(String, String, bool, String)> = cfg::host_entries(&self.host)
            .into_iter()
            .map(|e| (e.name, "this host".to_string(), e.enabled, format!("h:{}", e.line)))
            .collect();
        for module in self.module_names() {
            if cfg::is_host_module(&module) {
                continue; // already listed as "this host"
            }
            let active = cfg::is_active(&module, &enabled);
            for entry in cfg::module_entries(&module) {
                if entry.editable {
                    rows.push((entry.name, format!("{module}.nix"), active && entry.enabled, format!("m:{module}:{}", entry.line)));
                }
            }
        }
        rows.sort_by(|a, b| (a.0.to_lowercase(), &a.1).cmp(&(b.0.to_lowercase(), &b.1)));

        let t = self.theme.clone();
        let current = self.all_packages.current_id().map(str::to_string);
        let options: Vec<Row> = rows
            .iter()
            .filter(|(name, where_, _, _)| {
                query.is_empty() || name.to_lowercase().contains(&query) || where_.to_lowercase().contains(&query)
            })
            .map(|(name, where_, installed, key)| {
                let dot = if *installed { span("●", t.fg_of(t.primary)) } else { span("○", t.dim()) };
                let text = if *installed { plain(name.clone()) } else { span(name.clone(), t.dim()) };
                Row::option(key.clone(), vec![dot, plain(" "), text, plain(pad(name, 36, 2)), span(where_.clone(), t.dim())])
            })
            .collect();
        self.all_packages.set_rows(options);
        if let Some(c) = current {
            self.all_packages.select_id(&c);
        }
        let installed = rows.iter().filter(|r| r.2).count();
        self.tab_labels[1] = vec![plain("Packages "), span(installed.to_string(), t.dim())];
    }

    fn focused_list(&self) -> bool {
        matches!(self.focus, Focus::Modules | Focus::ModulePackages | Focus::AllPackages | Focus::Keybinds)
    }

    /// Whether a binding can run now (and shows in the footer).
    fn enabled(&self, action: Action) -> bool {
        if self.modal.is_some() {
            return false;
        }
        let modules_tab = self.tab == Tab::Modules;
        let packages_tab = self.tab == Tab::Packages;
        let on_modules = modules_tab && self.focus == Focus::Modules;
        match action {
            Action::DeleteModule => {
                let name = self.highlighted_module().unwrap_or(CORE.into());
                on_modules && !cfg::is_pinned(&name) && cfg::group_core(&name).as_deref() != Some(DESKTOP_CORE)
            }
            Action::DefaultDesktop => {
                on_modules && cfg::group_core(&self.highlighted_module().unwrap_or_default()).as_deref() == Some(DESKTOP_CORE)
            }
            Action::NewModule => on_modules,
            Action::Edit => modules_tab || (self.tab == Tab::Keybinds && self.highlighted_keybind().is_some()),
            Action::AddPackage => {
                // In the Modules tab: to the highlighted module (from either
                // column); in the Packages tab: to this host.
                packages_tab
                    || (modules_tab
                        && matches!(self.focus, Focus::Modules | Focus::ModulePackages)
                        && self.module.as_ref().is_some_and(|m| cfg::module_path(m).exists()))
            }
            Action::RemovePackage => {
                if self.focus == Focus::ModulePackages {
                    return self.highlighted_entry().is_some_and(|e| e.editable);
                }
                packages_tab && self.all_packages.current_id().is_some_and(|id| id.starts_with("h:"))
            }
            Action::FocusFilter => !modules_tab,
            Action::Hide => self.focused_list() && window::in_session(),
            _ => true,
        }
    }

    fn highlighted_entry(&self) -> Option<&modfile::Entry> {
        let line = self.highlighted_line()?;
        self.entries.iter().find(|e| e.line == line)
    }

    fn show_tab(&mut self, tab: Tab, jumping: bool) {
        if tab == self.tab {
            return;
        }
        self.tab = tab;
        if jumping {
            // coming from the Packages tab: keep the package focused
            self.focus = Focus::ModulePackages;
            return;
        }
        if tab == Tab::Keybinds {
            self.refresh_keybinds(); // the Lua files may have changed since
        }
        self.focus = match tab {
            Tab::Modules => Focus::Modules,
            Tab::Packages => Focus::AllPackages,
            Tab::Keybinds => Focus::Keybinds,
        };
        let list = self.list_mut(self.focus).unwrap();
        if list.highlighted.is_none() && list.len() > 0 {
            list.first(); // the first option that is not a heading
            if tab == Tab::Modules {
                self.module_highlighted();
            }
        }
    }

    fn list_mut(&mut self, focus: Focus) -> Option<&mut List> {
        match focus {
            Focus::Modules => Some(&mut self.modules),
            Focus::ModulePackages => Some(&mut self.packages),
            Focus::AllPackages => Some(&mut self.all_packages),
            Focus::Keybinds => Some(&mut self.keybinds),
            _ => None,
        }
    }

    fn save(&mut self) {
        if let Err(e) = cfg::save_state(&self.host, &self.state) {
            self.toast("", e, Severity::Error, 10);
        }
    }

    // Modules column

    fn module_toggled(&mut self) {
        let Some(name) = self.highlighted_module() else { return };
        if cfg::is_pinned(&name) {
            // can't be turned off
            let what = match name.as_str() {
                CORE => "core.nix is imported by every host: toggle its packages instead.",
                DESKTOP_CORE => {
                    "The desktop options are imported by core.nix: turn its desktops on or off instead (→ to open)."
                }
                _ => "configuration.nix is this host itself: toggle its packages instead.",
            };
            self.notify(what);
            return;
        }
        let on = !self.state.contains(&name);
        self.set_module(&name, on);
    }

    /// Turn a module on or off: in the host's imports, or for a submodule in
    /// its core.nix (shared by every host).
    fn set_module(&mut self, name: &str, on: bool) {
        if on && !self.state.iter().any(|n| n == name) {
            self.state.push(name.into());
        } else if !on {
            self.state.retain(|n| n != name);
        }
        match cfg::group_core(name) {
            Some(core) if core != DESKTOP_CORE => {
                // desktops are in the host file
                let subs: Vec<String> =
                    self.state.iter().filter(|n| cfg::group_core(n).as_deref() == Some(&core)).cloned().collect();
                match cfg::core_text(&core, &subs) {
                    Ok(text) => self.write_module(&core, text, None, false),
                    Err(e) => self.toast("", e, Severity::Error, 10),
                }
            }
            _ => self.save(),
        }
        self.refresh_all();
    }

    fn module_right(&mut self) {
        if let Some(name) = self.highlighted_module()
            && cfg::is_group(&name)
            && !self.expanded.contains(&name)
        {
            self.expanded.insert(name);
            self.refresh_modules();
            return;
        }
        if self.packages.len() > 0 {
            self.focus = Focus::ModulePackages;
            if self.packages.highlighted.is_none() {
                self.packages.first();
                self.show_preview(self.highlighted_line());
            }
        }
    }

    fn module_left(&mut self) {
        let name = self.highlighted_module().unwrap_or_default();
        let core = cfg::group_core(&name);
        if core.as_ref().is_some_and(|c| self.expanded.contains(c)) || self.expanded.contains(&name) {
            self.expanded.remove(&core.unwrap_or(name));
            self.refresh_modules();
        }
    }

    fn new_module(&mut self, name: String) {
        let name = name.strip_suffix(".nix").unwrap_or(&name).to_string();
        if !MODULE_NAME.is_match(&name) {
            return self.toast("", "Use a name like 'gaming' or 'folder/name'.", Severity::Error, 5);
        }
        let path = cfg::module_path(&name);
        if path.exists() {
            let file = path.file_name().unwrap_or_default().to_string_lossy();
            return self.toast("", format!("{file} already exists."), Severity::Error, 5);
        }
        if cfg::group_core(&name).as_deref() == Some(DESKTOP_CORE) {
            return self.toast(
                "",
                "A desktop also needs its session in desktop/default.nix: add it by hand (see that file).",
                Severity::Error,
                5,
            );
        }
        if let Err(e) = fs::create_dir_all(path.parent().unwrap()).and_then(|_| fs::write(&path, MODULE_TEMPLATE)) {
            return self.toast("", e.to_string(), Severity::Error, 10);
        }
        // Flakes only see files tracked by git.
        cfg::git(&["add", &posix(&path)]);
        self.set_module(&name, true);
        if let Some(core) = cfg::group_core(&name) {
            self.expanded.insert(core);
        }
        self.refresh_all();
        self.select_module(&name, None);
        self.open_editor(&path, None);
    }

    /// Highlight a module (opening its group) and show its packages.
    fn select_module(&mut self, name: &str, line: Option<usize>) {
        if let Some(core) = cfg::group_core(name)
            && !self.expanded.contains(&core)
        {
            self.expanded.insert(core);
            self.refresh_modules();
        }
        if self.modules.select_id(name) {
            self.module_highlighted();
        }
        self.show_module(Some(name.into()), Some(line));
    }

    fn edit(&mut self) {
        if self.tab == Tab::Keybinds {
            if let Some(bind) = self.highlighted_keybind() {
                let (path, line) = keybind_file(bind);
                self.open_editor(&path, line);
            }
            return;
        }
        let Some(name) = self.highlighted_module() else { return };
        let path = cfg::module_path(&name);
        if !path.exists() {
            return;
        }
        let line = if self.focus == Focus::ModulePackages { self.highlighted_line().map(|l| l + 1) } else { None };
        self.open_editor(&path, line);
    }

    fn open_editor(&mut self, path: &Path, line: Option<usize>) {
        let cmd = cfg::editor_command(path, line);
        let _ = self.suspend(|| Command::new(&cmd[0]).args(&cmd[1..]).status());
        self.refresh_all();
        self.show_module(self.module.clone(), None);
    }

    /// Preselect the highlighted desktop on this host's login screen (turning
    /// it on if needed).
    fn default_desktop(&mut self) {
        let Some(name) = self.highlighted_module() else { return };
        if cfg::group_core(&name).as_deref() != Some(DESKTOP_CORE) {
            return;
        }
        if !self.state.contains(&name) {
            self.state.push(name.clone());
            self.save();
        }
        let path = cfg::host_path(&self.host);
        let desktop = cfg::desktop_name(&name).to_string();
        match hostfile::set_default_session(&cfg::read(&path), &desktop) {
            Ok(text) => {
                if let Err(e) = fs::write(&path, text) {
                    return self.toast("", e.to_string(), Severity::Error, 10);
                }
            }
            Err(e) => return self.toast("", e, Severity::Error, 10),
        }
        self.refresh_all();
        self.notify(format!("{desktop} is the default desktop of {}.", self.host));
    }

    fn ask_delete_module(&mut self) {
        let Some(name) = self.highlighted_module() else { return };
        if cfg::is_pinned(&name) {
            return;
        }
        let path = cfg::module_path(&name);
        let file = path.file_name().unwrap_or_default().to_string_lossy().into_owned();
        let hosts: Vec<String> = cfg::list_hosts().into_iter().filter(|h| cfg::load_state(h).contains(&name)).collect();
        let importers = cfg::importers(&path);
        let bold = Style::default().add_modifier(Modifier::BOLD);
        let mut question = vec![vec![plain("Delete module "), span(name.clone(), bold), plain(format!(" ({file})?"))]];
        if !hosts.is_empty() {
            question.push(vec![plain(format!("It will be disabled on: {}.", hosts.join(", ")))]);
        }
        if cfg::list_modules().iter().any(|n| cfg::group_core(n).as_deref() == Some(&name)) {
            question.push(vec![plain("Its submodule files stay, but no host imports them anymore.")]);
        } else if let Some(core) = cfg::group_core(&name) {
            question.push(vec![plain(format!("It is removed from {core}.nix."))]);
        }
        if !importers.is_empty() {
            question.push(vec![
                span("Warning:", self.theme.fg_of(self.theme.warning)),
                plain(format!(" mentioned in {}.", importers.join(", "))),
            ]);
        }
        self.modal = Some(Modal::Confirm { question, purpose: ConfirmFor::DeleteModule(name) });
    }

    fn delete_module(&mut self, name: String) {
        let path = cfg::module_path(&name);
        let file = path.file_name().unwrap_or_default().to_string_lossy().into_owned();
        // Read every host before the file goes (its groups depend on it),
        // then save: saving drops the import lines of missing files.
        let core = cfg::group_core(&name);
        let mut gone: HashSet<String> =
            cfg::list_modules().into_iter().filter(|n| cfg::group_core(n).as_deref() == Some(&name)).collect();
        gone.insert(name.clone());
        let states: Vec<(String, Vec<String>)> = cfg::list_hosts()
            .into_iter()
            .map(|h| {
                let state = if h == self.host { self.state.clone() } else { cfg::load_state(&h) };
                (h, state)
            })
            .collect();
        let _ = fs::remove_file(&path);
        for (host, mut state) in states {
            state.retain(|n| !gone.contains(n));
            if host == self.host {
                self.state = state.clone();
            }
            if let Err(e) = cfg::save_state(&host, &state) {
                self.toast("", e, Severity::Error, 10);
            }
        }
        if let Some(core) = core {
            // drop its import line from the core
            match cfg::core_text(&core, &cfg::group_subs(&core)) {
                Ok(text) => {
                    let _ = fs::write(cfg::module_path(&core), text);
                }
                Err(e) => self.toast("", e, Severity::Error, 10),
            }
        }
        if let Some(parent) = path.parent()
            && parent != cfg::MODULES_DIR.as_path()
            && fs::read_dir(parent).is_ok_and(|mut d| d.next().is_none())
        {
            let _ = fs::remove_dir(parent);
        }
        cfg::git(&["rm", "-q", "--cached", "--ignore-unmatch", &posix(&path)]);
        self.expanded.remove(&name);
        self.refresh_all();
        self.notify(format!("Deleted {file}."));
    }

    // Packages of a module (comment / uncomment lines)

    fn package_toggled(&mut self) {
        let Some(entry) = self.highlighted_entry().cloned() else { return };
        let Some(module) = self.module.clone() else { return };
        if !entry.editable {
            return;
        }
        let text = cfg::read(&cfg::module_path(&module));
        self.write_module(&module, modfile::toggle(&text, &entry), Some(entry.line), true);
    }

    /// Save a module change, then check it with Nix in the background.
    fn write_module(&mut self, name: &str, text: String, line: Option<usize>, show: bool) {
        let path = cfg::module_path(name);
        self.good.entry(path.clone()).or_insert_with(|| cfg::read(&path));
        if let Err(e) = fs::write(&path, &text) {
            return self.toast("", e.to_string(), Severity::Error, 10);
        }
        self.check_status = Some(vec![span("checking…", self.theme.dim())]);
        if show {
            self.show_module(Some(name.into()), Some(line));
        } else if self.module.is_some() {
            self.show_module(self.module.clone(), None);
        }
        self.refresh_all_packages();
        // A newer check replaces this one (its result is ignored).
        self.check_id += 1;
        let (id, tx, name) = (self.check_id, self.tx.clone(), name.to_string());
        std::thread::spawn(move || {
            let error = cfg::check_module(&name);
            let _ = tx.send(Msg::Checked { id, name, text, error });
        });
    }

    fn checked(&mut self, name: String, text: String, error: Option<String>) {
        let path = cfg::module_path(&name);
        if cfg::read(&path) != text {
            return; // changed again since: a newer check is running
        }
        let file = path.file_name().unwrap_or_default().to_string_lossy().into_owned();
        if let Some(error) = error {
            if let Some(good) = self.good.remove(&path) {
                let _ = fs::write(&path, good);
            }
            self.check_status = Some(vec![span("reverted", self.theme.fg_of(self.theme.error))]);
            self.state = cfg::load_state(&self.host); // a reverted core.nix
            self.refresh_modules();
            self.toast("Nix check failed", format!("{error}\n\nThe change to {file} was reverted."), Severity::Error, 10);
        } else {
            self.good.remove(&path);
            self.check_status = Some(vec![span("✓", self.theme.fg_of(self.theme.success))]);
        }
        if self.module.as_deref() == Some(&name) {
            self.show_module(Some(name), None);
        }
        self.refresh_all_packages();
    }

    // Packages: add / remove (to the module in focus, or to this host)

    fn add_package(&mut self) {
        let target = match &self.module {
            Some(m) if self.tab == Tab::Modules && !cfg::is_host_module(m) => AddTarget::Module(m.clone()),
            _ => AddTarget::Host,
        };
        let title = match &target {
            AddTarget::Module(m) => cfg::module_path(m).file_name().unwrap_or_default().to_string_lossy().into_owned(),
            AddTarget::Host => "this host".into(),
        };
        self.modal = Some(Modal::Search {
            target,
            title: format!("Add a package to {title}: type a search and press Enter"),
            input: Input::new("e.g. firefox, or kdePackages.kate"),
            status: vec![],
            list: List::default(),
            on_results: false,
            id: 0,
        });
    }

    fn add_to(&mut self, target: AddTarget, attr: String, comment: String) {
        match target {
            AddTarget::Module(module) => {
                let path = cfg::module_path(&module);
                let file = path.file_name().unwrap_or_default().to_string_lossy().into_owned();
                let text = cfg::read(&path);
                if modfile::entries(&text).iter().any(|e| e.name == attr) {
                    return self.notify(format!("{attr} is already in {file}."));
                }
                match modfile::add(&text, &attr, &comment) {
                    None => self.toast(
                        "",
                        format!("{file} has no environment.systemPackages list: press e to add one."),
                        Severity::Warning,
                        5,
                    ),
                    Some((text, line)) => self.write_module(&module, text, Some(line), true),
                }
            }
            AddTarget::Host => {
                let path = cfg::host_path(&self.host);
                let file = path.file_name().unwrap_or_default().to_string_lossy().into_owned();
                let text = cfg::read(&path);
                let existing = cfg::host_entries(&self.host).into_iter().find(|e| e.name == attr);
                if existing.as_ref().is_some_and(|e| e.enabled) {
                    return self.notify(format!("{attr} is already installed on this host."));
                }
                let new = if let Some(existing) = existing {
                    modfile::toggle(&text, &existing) // commented out: uncomment it
                } else {
                    match modfile::add(&text, &attr, &comment) {
                        Some((new, _)) => new,
                        None => {
                            // no list yet, or one closed on an item line
                            if modfile::parse(&text).iter().any(|b| b.close.is_none()) {
                                return self.toast(
                                    "",
                                    format!("Can't add to the package list of {file}: edit it by hand."),
                                    Severity::Warning,
                                    5,
                                );
                            }
                            match modfile::add(&hostfile::add_packages_block(&text), &attr, &comment) {
                                Some((new, _)) => new,
                                None => return,
                            }
                        }
                    }
                };
                if let Err(e) = fs::write(&path, new) {
                    return self.toast("", e.to_string(), Severity::Error, 10);
                }
                self.refresh_all_packages();
                if self.module.as_deref().is_some_and(cfg::is_host_module) {
                    self.show_module(self.module.clone(), None); // its row in the Modules tab
                }
                self.notify(format!("Added {attr} to this host."));
            }
        }
    }

    fn remove_package(&mut self) {
        if self.focus == Focus::ModulePackages {
            if let (Some(entry), Some(module)) = (self.highlighted_entry().cloned(), self.module.clone())
                && entry.editable
            {
                let path = cfg::module_path(&module);
                let text = cfg::read(&path);
                self.write_module(&module, modfile::remove(&text, &entry), Some(entry.line), true);
                let file = path.file_name().unwrap_or_default().to_string_lossy().into_owned();
                self.notify(format!("Removed {} from {file}.", entry.name));
            }
            return;
        }
        let Some(id) = self.all_packages.current_id().map(str::to_string) else { return };
        if let Some(entry) = self.host_entry(&id) {
            let path = cfg::host_path(&self.host);
            let _ = fs::write(&path, modfile::remove(&cfg::read(&path), &entry));
            self.refresh_all_packages();
            self.notify(format!("Removed {} from this host.", entry.name));
        }
    }

    fn host_entry(&self, id: &str) -> Option<modfile::Entry> {
        let line: usize = id.strip_prefix("h:")?.parse().ok()?;
        cfg::host_entries(&self.host).into_iter().find(|e| e.line == line)
    }

    /// Enter in the Packages tab: jump to the module a package comes from, or
    /// toggle a host package.
    fn package_selected(&mut self) {
        let Some(id) = self.all_packages.current_id().map(str::to_string) else { return };
        if id.starts_with("h:") {
            if let Some(entry) = self.host_entry(&id) {
                let path = cfg::host_path(&self.host);
                let _ = fs::write(&path, modfile::toggle(&cfg::read(&path), &entry));
                self.refresh_all_packages();
            }
            return;
        }
        let mut parts = id.splitn(3, ':').skip(1);
        let (Some(module), Some(line)) = (parts.next(), parts.next().and_then(|l| l.parse().ok())) else { return };
        let module = module.to_string();
        self.show_tab(Tab::Modules, true);
        self.select_module(&module, Some(line));
    }

    // Keybinds tab (read-only)

    /// Caelestia's binds with the hypr-vars.lua overrides, then hypr-user.lua's.
    fn refresh_keybinds(&mut self) {
        self.hypr_binds = keybinds::load(&DOTFILES);
        let query = self.kb_filter.value.trim().to_lowercase();
        let current = self.keybinds.current_id().map(str::to_string);
        let t = self.theme.clone();
        let mut options = Vec::new();
        let mut section: Option<&str> = None;
        for (i, bind) in self.hypr_binds.iter().enumerate() {
            let text = [
                bind.combo.as_str(),
                &bind.default,
                &bind.label,
                &bind.action,
                bind.source,
                &bind.var,
                &bind.section,
                if bind.conflict { "conflict" } else { "" },
                if bind.disabled() { "removed" } else { "" },
            ]
            .join(" ")
            .to_lowercase();
            if !query.is_empty() && !text.contains(&query) {
                continue;
            }
            if section != Some(bind.section.as_str()) {
                section = Some(&bind.section);
                let heading = if bind.section.is_empty() { "Caelestia".to_string() } else { bind.section.clone() };
                options.push(
                    Row::option(format!("section:{i}"), vec![span(heading, t.fg_of(t.primary).add_modifier(Modifier::BOLD))])
                        .disabled(true),
                );
            }
            options.push(Row::option(format!("bind:{i}"), keybind_row(&t, bind)));
        }
        self.keybinds.set_rows(options);
        if let Some(c) = current {
            self.keybinds.select_id(&c);
        }
        let conflicts = self.hypr_binds.iter().filter(|b| b.conflict).count();
        let mut label = vec![
            plain("Keybinds "),
            span(self.hypr_binds.iter().filter(|b| !b.disabled()).count().to_string(), t.dim()),
        ];
        if conflicts > 0 {
            label.push(span(format!(" !{conflicts}"), t.fg_of(t.error)));
        }
        self.tab_labels[2] = label;
    }

    fn highlighted_keybind(&self) -> Option<&Bind> {
        let id = self.keybinds.current_id()?;
        let i: usize = id.strip_prefix("bind:")?.parse().ok()?;
        self.hypr_binds.get(i)
    }

    fn keybind_detail(&self) -> Vec<Spans> {
        let t = &self.theme;
        let Some(bind) = self.highlighted_keybind() else { return vec![] };
        let mut first = String::new();
        if !bind.var.is_empty() {
            first += &format!("{} · ", bind.var);
        }
        first += &format!("{}:{}", cfg::display_path(&bind.path), bind.line);
        if !bind.flags.is_empty() {
            first += &format!(" · {}", bind.flags.join(", "));
        }
        let mut lines =
            vec![vec![plain(first), span(format!("  e: open {}", cfg::display_path(&keybind_file(bind).0)), t.dim())]];
        if bind.conflict {
            let key = keybinds::combo_key(&bind.combo);
            let others: Vec<&str> = self
                .hypr_binds
                .iter()
                .filter(|b| {
                    !std::ptr::eq(*b, bind)
                        && !b.combo.is_empty()
                        && b.flags.iter().filter(|f| *f == "release").count()
                            == bind.flags.iter().filter(|f| *f == "release").count()
                        && keybinds::combo_key(&b.combo) == key
                })
                .map(|b| b.label.as_str())
                .collect();
            lines.push(vec![
                span("Same combo as: ", t.fg_of(t.error)),
                plain(others.join(" · ")),
                span("  (all of them run)", t.dim()),
            ]);
        } else if bind.disabled() {
            lines.push(vec![plain(format!("Removed by {} = \"\" in hypr-vars.lua", bind.var))]);
        }
        lines
    }

    // Host and system

    fn git_diff(&mut self) {
        let diff = ["diff", "HEAD"];
        let paths = ["--", "nixos", "flake.lock"];
        // --quiet must come before "--", or git takes it as a path and prints
        // the whole diff over the TUI.
        let quiet: Vec<&str> = diff.iter().chain(&["--quiet"]).chain(&paths).copied().collect();
        if cfg::git(&quiet) {
            return self.notify("No changes since the last commit.");
        }
        // Git defaults to LESS=FRX, and F quits at once when the diff fits on
        // one screen, so the TUI would redraw over it before it can be read.
        // c clears the screen first, or the diff is drawn over the TUI.
        let _ = self.suspend(|| {
            Command::new("git").arg("-C").arg(&*DOTFILES).args(diff).args(paths).env("LESS", "Rc").status()
        });
    }

    fn ask_update(&mut self) {
        // With nh, updating this machine also switches to the updated config.
        let switch = cfg::has_nh() && self.host == self.hostname;
        let cmd: Vec<String> = if switch {
            ["nh", "os", "switch", "--update"].map(String::from).into_iter().chain(cfg::nh_args(&self.host)).collect()
        } else {
            vec!["nix".into(), "flake".into(), "update".into(), "--flake".into(), posix(&DOTFILES)]
        };
        // flake.lock is shared, so this updates every host, not just this one.
        let mut question = "Update every flake input (flake.lock, all hosts)".to_string();
        question += &if switch { format!(" and switch {}?", self.host) } else { "?".into() };
        self.modal = Some(Modal::Confirm { question: vec![vec![plain(question)]], purpose: ConfirmFor::Run { cmd, what: "update" } });
    }

    fn build(&mut self) {
        let cmd: Vec<String> = if cfg::has_nh() {
            ["nh", "os", "build"].map(String::from).into_iter().chain(cfg::nh_args(&self.host)).collect()
        } else {
            let attr = format!("{}#nixosConfigurations.{}.config.system.build.toplevel", posix(&DOTFILES), self.host);
            ["nix", "build", "--no-link"].map(String::from).into_iter().chain(cfg::flake_args(&self.host)).chain([attr]).collect()
        };
        self.run_command(cmd, "build");
    }

    fn ask_rebuild(&mut self) {
        if self.host != self.hostname {
            let msg = format!("This machine is {}, not {}: use Build (b) to test it instead.", self.hostname, self.host);
            return self.toast("", msg, Severity::Error, 5);
        }
        let cmd: Vec<String> = if cfg::has_nh() {
            ["nh", "os", "switch"].map(String::from).into_iter().chain(cfg::nh_args(&self.host)).collect()
        } else {
            ["sudo", "nixos-rebuild", "switch"]
                .map(String::from)
                .into_iter()
                .chain(cfg::flake_args(&self.host))
                .chain(["--flake".into(), format!("{}#{}", posix(&DOTFILES), self.host)])
                .collect()
        };
        let question = format!("Run {} for {}?", cmd[..3].join(" "), self.host);
        self.modal = Some(Modal::Confirm { question: vec![vec![plain(question)]], purpose: ConfirmFor::Run { cmd, what: "rebuild" } });
    }

    fn generations(&mut self) {
        if self.host != self.hostname {
            let msg = format!("Generations are per machine: this one is {}.", self.hostname);
            return self.toast("", msg, Severity::Error, 5);
        }
        let mut list = List::default();
        let bold = Style::default().add_modifier(Modifier::BOLD);
        list.set_rows(
            cfg::list_generations()
                .into_iter()
                .map(|g| {
                    let mut label = vec![plain(format!("{:>4}  {}  {}  linux {}", g.number, g.date, g.version, g.kernel))];
                    let tags: Vec<&str> =
                        [("current", g.current), ("running", g.running)].iter().filter(|t| t.1).map(|t| t.0).collect();
                    if !tags.is_empty() {
                        label.push(plain("  "));
                        label.push(span(format!("({})", tags.join(", ")), bold));
                    }
                    Row::selection(g.number.to_string(), label, false).disabled(g.current)
                })
                .collect(),
        );
        list.first();
        self.modal = Some(Modal::Generations { list, selected: HashSet::new() });
    }

    fn delete_generations(&mut self, numbers: Vec<u32>) {
        let quote = |args: &[String]| args.iter().map(|a| shell_quote(a)).collect::<Vec<_>>().join(" ");
        let mut delete = vec!["sudo".to_string(), "nix-env".into(), "--profile".into(), SYSTEM_PROFILE.into(), "--delete-generations".into()];
        delete.extend(numbers.iter().map(|n| n.to_string()));
        let steps = [
            delete,
            // Rewrites the boot menu without them, like nixos-rebuild boot.
            vec!["sudo".into(), format!("{SYSTEM_PROFILE}/bin/switch-to-configuration"), "boot".into()],
            // Frees their store paths that nothing else uses.
            vec!["nix-collect-garbage".into()],
        ];
        let script = steps.iter().map(|s| quote(s)).collect::<Vec<_>>().join(" && ");
        let cmd = vec!["sh".into(), "-c".into(), script];
        let plural = if numbers.len() > 1 { "s" } else { "" };
        let question = format!(
            "Delete generation{plural} {}, update the boot menu and collect garbage?",
            cfg::number_ranges(&numbers)
        );
        self.modal =
            Some(Modal::Confirm { question: vec![vec![plain(question)]], purpose: ConfirmFor::Run { cmd, what: "generation cleanup" } });
    }

    fn switch_host(&mut self) {
        let mut list = List::default();
        list.set_rows(cfg::list_hosts().into_iter().map(|h| Row::option(h.clone(), vec![plain(h)])).collect());
        list.first();
        self.modal = Some(Modal::Choose { title: "Host to edit".into(), list });
    }

    fn run_action(&mut self, action: Action) {
        if !self.enabled(action) {
            return;
        }
        match action {
            Action::Tab(tab) => self.show_tab(tab, false),
            Action::SwitchHost => self.switch_host(),
            Action::NewModule => {
                self.modal = Some(Modal::Prompt {
                    title: "New module name".into(),
                    input: Input::new("e.g. music or epita/rust"),
                    allow_empty: false,
                    purpose: PromptFor::NewModule,
                })
            }
            Action::Edit => self.edit(),
            Action::DeleteModule => self.ask_delete_module(),
            Action::DefaultDesktop => self.default_desktop(),
            Action::AddPackage => self.add_package(),
            Action::RemovePackage => self.remove_package(),
            Action::FocusFilter => self.focus = if self.tab == Tab::Keybinds { Focus::KbFilter } else { Focus::Filter },
            Action::GitDiff => self.git_diff(),
            Action::Update => self.ask_update(),
            Action::Build => self.build(),
            Action::Rebuild => self.ask_rebuild(),
            Action::Generations => self.generations(),
            Action::ToggleTheme => self.toggle_theme(),
            Action::Quit => self.quit = true,
            Action::Hide => {
                window::hide();
            }
        }
    }

    // Events

    fn on_msg(&mut self, msg: Msg) {
        match msg {
            Msg::Quit => self.quit = true,
            Msg::Checked { id, name, text, error } => {
                if id == self.check_id {
                    self.checked(name, text, error);
                }
            }
            Msg::Searched { id, found, total, error } => self.show_results(id, found, total, error),
        }
    }

    fn on_key(&mut self, key: KeyEvent) {
        let ctrl = key.modifiers.contains(KeyModifiers::CONTROL);
        if ctrl && matches!(key.code, KeyCode::Char('q') | KeyCode::Char('c')) {
            self.quit = true;
            return;
        }
        if self.modal.is_some() {
            return self.modal_key(key);
        }
        if matches!(key.code, KeyCode::Tab | KeyCode::BackTab) {
            return self.cycle_focus(key.code == KeyCode::Tab);
        }
        match self.focus {
            Focus::Filter | Focus::KbFilter => {
                let list = if self.focus == Focus::Filter { Focus::AllPackages } else { Focus::Keybinds };
                match key.code {
                    KeyCode::Esc | KeyCode::Enter | KeyCode::Down => self.focus = list,
                    _ => {
                        let input = if self.focus == Focus::Filter { &mut self.filter } else { &mut self.kb_filter };
                        if input.key(&key) == Some(true) {
                            if self.focus == Focus::Filter {
                                self.refresh_all_packages();
                            } else {
                                self.refresh_keybinds();
                            }
                        }
                    }
                }
            }
            focus => {
                let list = self.list_mut(focus).unwrap();
                if let Some(changed) = list.nav_key(&key) {
                    if changed {
                        self.highlight_changed(focus);
                    }
                    return;
                }
                match (focus, key.code) {
                    (Focus::Modules, KeyCode::Char(' ') | KeyCode::Enter) => self.module_toggled(),
                    (Focus::Modules, KeyCode::Right) => self.module_right(),
                    (Focus::Modules, KeyCode::Left) => self.module_left(),
                    (Focus::ModulePackages, KeyCode::Char(' ') | KeyCode::Enter) => self.package_toggled(),
                    (Focus::ModulePackages, KeyCode::Left) => self.focus = Focus::Modules,
                    (Focus::AllPackages, KeyCode::Enter) => self.package_selected(),
                    (_, KeyCode::Esc) => self.run_action(Action::Hide),
                    (_, KeyCode::Delete) => self.run_action(Action::RemovePackage),
                    (_, KeyCode::Char(c)) => {
                        let key = c.to_string();
                        if let Some((_, _, action)) = BINDINGS.iter().find(|(k, _, _)| *k == key) {
                            self.run_action(*action);
                        }
                    }
                    _ => {}
                }
            }
        }
    }

    fn highlight_changed(&mut self, focus: Focus) {
        match focus {
            Focus::Modules => self.module_highlighted(),
            Focus::ModulePackages => self.show_preview(self.highlighted_line()),
            _ => {}
        }
    }

    fn cycle_focus(&mut self, forward: bool) {
        let order: &[Focus] = match self.tab {
            Tab::Modules => &[Focus::Modules, Focus::ModulePackages],
            Tab::Packages => &[Focus::Filter, Focus::AllPackages],
            Tab::Keybinds => &[Focus::KbFilter, Focus::Keybinds],
        };
        let i = order.iter().position(|f| *f == self.focus).unwrap_or(0);
        let next = if forward { (i + 1) % order.len() } else { (i + order.len() - 1) % order.len() };
        self.focus = order[next];
        if self.focus == Focus::ModulePackages && self.packages.highlighted.is_none() {
            self.packages.first();
            self.show_preview(self.highlighted_line());
        }
    }

    fn modal_key(&mut self, key: KeyEvent) {
        let Some(mut modal) = self.modal.take() else { return };
        let esc = key.code == KeyCode::Esc;
        match &mut modal {
            Modal::Prompt { input, allow_empty, .. } => {
                if esc {
                    return;
                }
                if key.code == KeyCode::Enter {
                    let value = input.value.trim().to_string();
                    let allow = *allow_empty;
                    let Modal::Prompt { purpose, .. } = modal else { unreachable!() };
                    if value.is_empty() && !allow {
                        return;
                    }
                    return match purpose {
                        PromptFor::NewModule => self.new_module(value),
                        PromptFor::Description { target, attr } => self.add_to(target, attr, value),
                    };
                }
                input.key(&key);
            }
            Modal::Confirm { .. } => match key.code {
                KeyCode::Char('y') => {
                    let Modal::Confirm { purpose, .. } = modal else { unreachable!() };
                    return match purpose {
                        ConfirmFor::DeleteModule(name) => self.delete_module(name),
                        ConfirmFor::Run { cmd, what } => self.run_command(cmd, what),
                    };
                }
                KeyCode::Char('n') | KeyCode::Esc => return,
                _ => {}
            },
            Modal::Choose { list, .. } => {
                if esc {
                    return;
                }
                if key.code == KeyCode::Enter {
                    if let Some(host) = list.current_id().map(str::to_string) {
                        self.host = host.clone();
                        self.state = cfg::load_state(&host);
                        self.refresh_all();
                    }
                    return;
                }
                list.nav_key(&key);
            }
            Modal::Generations { list, selected } => match key.code {
                KeyCode::Esc => return,
                KeyCode::Char('d') => {
                    let mut numbers: Vec<u32> = selected.iter().copied().collect();
                    numbers.sort();
                    if !numbers.is_empty() {
                        self.delete_generations(numbers);
                    }
                    return;
                }
                KeyCode::Char('o') => {
                    if let Some(h) = list.highlighted {
                        for row in list.rows.iter_mut().skip(h + 1).filter(|r| !r.disabled) {
                            row.selected = Some(true);
                            selected.insert(row.id.parse().unwrap_or(0));
                        }
                    }
                }
                KeyCode::Char(' ') | KeyCode::Enter => {
                    if let Some(h) = list.highlighted
                        && !list.rows[h].disabled
                    {
                        let row = &mut list.rows[h];
                        let on = !row.selected.unwrap_or(false);
                        row.selected = Some(on);
                        let n: u32 = row.id.parse().unwrap_or(0);
                        if on {
                            selected.insert(n);
                        } else {
                            selected.remove(&n);
                        }
                    }
                }
                _ => {
                    list.nav_key(&key);
                }
            },
            Modal::Search { input, list, on_results, target, .. } => {
                if esc {
                    return;
                }
                if *on_results {
                    match key.code {
                        KeyCode::Enter => {
                            if let Some(attr) = list.current_id().map(str::to_string) {
                                let target = target.clone();
                                self.ask_description(target, attr);
                            }
                            return;
                        }
                        KeyCode::Tab | KeyCode::BackTab => *on_results = false,
                        KeyCode::Up if list.highlighted == Some(0) => *on_results = false,
                        _ => {
                            if list.nav_key(&key).is_none()
                                && let KeyCode::Char(_) = key.code
                            {
                                // Typing goes back to the search field.
                                *on_results = false;
                                input.key(&key);
                            }
                        }
                    }
                } else {
                    match key.code {
                        KeyCode::Enter => {
                            let query = input.value.trim().to_string();
                            if !query.is_empty() {
                                self.modal = Some(modal);
                                return self.search(query);
                            }
                        }
                        KeyCode::Tab | KeyCode::BackTab | KeyCode::Down if list.len() > 0 => *on_results = true,
                        _ => {
                            input.key(&key);
                        }
                    }
                }
            }
        }
        self.modal = Some(modal);
    }

    /// Ask for an optional description of the chosen package (written as a
    /// "# comment" after it), then add it.
    fn ask_description(&mut self, target: AddTarget, attr: String) {
        self.modal = Some(Modal::Prompt {
            title: format!("Description of {attr} (optional, Enter to skip)"),
            input: Input::new("e.g. Terminal"),
            allow_empty: true,
            purpose: PromptFor::Description { target, attr },
        });
    }

    /// Search the flake's locked nixpkgs in the background.
    fn search(&mut self, query: String) {
        self.search_id += 1;
        let id = self.search_id;
        let t = self.theme.clone();
        if let Some(Modal::Search { list, on_results, status, id: modal_id, .. }) = &mut self.modal {
            let bold = Style::default().add_modifier(Modifier::BOLD);
            list.set_rows(vec![Row::option(query.clone(), vec![plain("Add "), span(query.clone(), bold), plain(" as-is")])]);
            // Enter again adds the typed name; search results show up below it.
            list.highlighted = Some(0);
            *on_results = true;
            *status = vec![span("Searching nixpkgs... (the first search can take a minute)", t.muted())];
            *modal_id = id;
        }
        let tx = self.tx.clone();
        std::thread::spawn(move || {
            let out = Command::new("nix")
                .args(["search", "--inputs-from"])
                .arg(&*DOTFILES)
                .arg("nixpkgs")
                .args(query.split_whitespace())
                .arg("--json")
                .stdin(std::process::Stdio::null())
                .output();
            let (found, total, error) = match out {
                Ok(out) => {
                    let json: serde_json::Map<String, serde_json::Value> =
                        serde_json::from_slice(&out.stdout).unwrap_or_default();
                    let total = json.len();
                    let found = json
                        .iter()
                        .take(200)
                        .map(|(key, info)| {
                            // "legacyPackages.x86_64-linux.kdePackages.kate" -> "kdePackages.kate"
                            let attr = key.splitn(3, '.').nth(2).unwrap_or(key).to_string();
                            let get = |k| info.get(k).and_then(|v| v.as_str()).unwrap_or("").to_string();
                            (attr, get("version"), get("description"))
                        })
                        .collect();
                    let error =
                        if out.status.success() { String::new() } else { cfg::nix_error(&String::from_utf8_lossy(&out.stderr)) };
                    (found, total, error)
                }
                Err(e) => (vec![], 0, e.to_string()),
            };
            let _ = tx.send(Msg::Searched { id, found, total, error });
        });
    }

    fn show_results(&mut self, id: u64, found: Vec<SearchResult>, total: usize, error: String) {
        let t = self.theme.clone();
        let Some(Modal::Search { list, status, input, id: modal_id, .. }) = &mut self.modal else { return };
        if *modal_id != id {
            return;
        }
        let bold = Style::default().add_modifier(Modifier::BOLD);
        let typed = input.value.trim().to_string();
        for (attr, version, desc) in found {
            let label = vec![span(attr.clone(), bold), plain(" "), span(version, t.dim()), plain(format!("  {desc}"))];
            if attr == typed {
                // The exact name typed: describe the "as-is" entry instead.
                if let Some(row) = list.rows.iter_mut().find(|r| r.id == attr) {
                    row.label = label;
                }
            } else {
                list.rows.push(Row::option(attr, label));
            }
        }
        *status = if !error.is_empty() {
            vec![span("nix search failed: ", t.fg_of(t.error)), plain(error)]
        } else {
            let more = if total > 200 { " (showing 200)" } else { "" };
            vec![span(format!("{total} result(s){more}"), t.muted())]
        };
    }

    fn on_mouse(&mut self, m: MouseEvent) {
        let (col, row) = (m.column, m.row);
        match m.kind {
            MouseEventKind::ScrollDown | MouseEventKind::ScrollUp => {
                let delta = if m.kind == MouseEventKind::ScrollDown { 3 } else { -3 };
                if let Some(modal) = &mut self.modal {
                    if let Modal::Choose { list, .. } | Modal::Generations { list, .. } | Modal::Search { list, .. } = modal {
                        list.scroll(delta);
                    }
                    return;
                }
                if self.preview_area.contains(Position::new(col, row)) {
                    let max = self.preview.len().saturating_sub(self.preview_area.height as usize);
                    self.preview_scroll = (self.preview_scroll as isize + delta).clamp(0, max as isize) as usize;
                    return;
                }
                for focus in [Focus::Modules, Focus::ModulePackages, Focus::AllPackages, Focus::Keybinds] {
                    let list = self.list_mut(focus).unwrap();
                    if list.area.contains(Position::new(col, row)) {
                        list.scroll(delta);
                    }
                }
            }
            MouseEventKind::Down(MouseButton::Left) => {
                if let Some(mut modal) = self.modal.take() {
                    let mut chosen = None;
                    match &mut modal {
                        Modal::Choose { list, .. } => {
                            if let Some(i) = list.row_at(col, row) {
                                list.highlighted = Some(i);
                                chosen = Some(KeyCode::Enter);
                            }
                        }
                        Modal::Generations { list, .. } => {
                            if let Some(i) = list.row_at(col, row).filter(|i| !list.rows[*i].disabled) {
                                list.highlighted = Some(i);
                                chosen = Some(KeyCode::Char(' '));
                            }
                        }
                        Modal::Search { list, on_results, input, .. } => {
                            if let Some(i) = list.row_at(col, row) {
                                list.highlighted = Some(i);
                                *on_results = true;
                                chosen = Some(KeyCode::Enter);
                            } else if input.contains(col, row) {
                                *on_results = false;
                            }
                        }
                        _ => {}
                    }
                    self.modal = Some(modal);
                    if let Some(code) = chosen {
                        self.modal_key(KeyEvent::new(code, KeyModifiers::NONE));
                    }
                    return;
                }
                if let Some((_, tab)) = self.tab_areas.iter().find(|(a, _)| a.contains(Position::new(col, row))) {
                    let tab = *tab;
                    return self.show_tab(tab, false);
                }
                if let Some((_, action)) = self.footer_areas.iter().find(|(a, _)| a.contains(Position::new(col, row))) {
                    let action = *action;
                    return self.run_action(action);
                }
                if self.filter.contains(col, row) && self.tab == Tab::Packages {
                    self.focus = Focus::Filter;
                    return;
                }
                if self.kb_filter.contains(col, row) && self.tab == Tab::Keybinds {
                    self.focus = Focus::KbFilter;
                    return;
                }
                let lists: &[Focus] = match self.tab {
                    Tab::Modules => &[Focus::Modules, Focus::ModulePackages],
                    Tab::Packages => &[Focus::AllPackages],
                    Tab::Keybinds => &[Focus::Keybinds],
                };
                for &focus in lists {
                    let list = self.list_mut(focus).unwrap();
                    let Some(i) = list.row_at(col, row) else { continue };
                    if list.rows[i].disabled && focus != Focus::ModulePackages {
                        return;
                    }
                    let changed = list.highlighted != Some(i);
                    list.highlighted = Some(i);
                    self.focus = focus;
                    if changed {
                        self.highlight_changed(focus);
                    }
                    // A click selects, like Textual's lists.
                    match focus {
                        Focus::Modules => self.module_toggled(),
                        Focus::ModulePackages => self.package_toggled(),
                        Focus::AllPackages => self.package_selected(),
                        _ => {}
                    }
                    return;
                }
            }
            _ => {}
        }
    }

    // Drawing

    fn render(&mut self, f: &mut Frame) {
        let t = self.theme.clone();
        let area = f.area();
        self.width = area.width;
        f.render_widget(Block::default().style(t.base()), area);
        if area.height < 8 || area.width < 20 {
            return;
        }

        // Title bar
        let mut title = vec![
            span("nixcfg", t.fg_of(t.primary).add_modifier(Modifier::BOLD)),
            plain("  "),
            span("•", t.dim()),
            plain("  "),
            span(self.host.clone(), Style::default().add_modifier(Modifier::BOLD)),
        ];
        if self.host == self.hostname {
            title.push(plain("  "));
            title.push(span("this machine", t.dim()));
        }
        f.render_widget(Paragraph::new(Line::from(title)), Rect::new(area.x + 2, area.y + 1, area.width - 4, 1));

        // Tabs (margin 0 1): labels, then the underline bar.
        let tabs_x = area.x + 1;
        let tabs_w = area.width - 2;
        let mut x = tabs_x;
        self.tab_areas.clear();
        let bar_y = area.y + 3;
        f.render_widget(
            Paragraph::new("━".repeat(tabs_w as usize)).style(Style::default().fg(if t.ansi { Color::DarkGray } else { t.mix(t.fg, 0.08) })),
            Rect::new(tabs_x, bar_y, tabs_w, 1),
        );
        for (i, tab) in [Tab::Modules, Tab::Packages, Tab::Keybinds].into_iter().enumerate() {
            let label = self.tab_labels[i].clone();
            let w = spans_width(&label) as u16 + 2;
            if x + w > tabs_x + tabs_w {
                break;
            }
            let active = tab == self.tab;
            let style = if active { t.fg_of(t.primary).add_modifier(Modifier::BOLD) } else { t.muted() };
            let spans: Spans = std::iter::once(plain(" "))
                .chain(label.into_iter().map(|s| if s.style.fg.is_none() { Span::styled(s.content, style) } else { s }))
                .chain(std::iter::once(plain(" ")))
                .collect();
            let rect = Rect::new(x, area.y + 2, w, 1);
            f.render_widget(Paragraph::new(Line::from(spans)), rect);
            if active {
                f.render_widget(Paragraph::new("━".repeat(w as usize)).style(t.fg_of(t.primary)), Rect::new(x, bar_y, w, 1));
            }
            self.tab_areas.push((Rect::new(x, area.y + 2, w, 2), tab));
            x += w;
        }

        // Content, between the tabs (and their padding) and the footer
        let content = Rect::new(tabs_x, area.y + 5, tabs_w, area.height.saturating_sub(6));
        match self.tab {
            Tab::Modules => self.render_modules(f, content, &t),
            Tab::Packages => {
                let input = Rect::new(content.x + 1, content.y, content.width.saturating_sub(2), 3);
                self.filter.render(f, input, self.focus == Focus::Filter, &t, t.bg);
                let list = Rect::new(content.x, content.y + 4, content.width, content.height.saturating_sub(4));
                self.all_packages.render(f, list, self.focus == Focus::AllPackages, &t, t.bg);
            }
            Tab::Keybinds => {
                let input = Rect::new(content.x + 1, content.y, content.width.saturating_sub(2), 3);
                self.kb_filter.render(f, input, self.focus == Focus::KbFilter, &t, t.bg);
                let list = Rect::new(content.x, content.y + 4, content.width, content.height.saturating_sub(7));
                self.keybinds.render(f, list, self.focus == Focus::Keybinds, &t, t.bg);
                let detail: Vec<Line> = self.keybind_detail().into_iter().map(Line::from).collect();
                let detail_area = Rect::new(content.x + 2, content.y + content.height.saturating_sub(2), content.width.saturating_sub(4), 2);
                f.render_widget(Paragraph::new(detail).style(t.muted()), detail_area);
            }
        }

        self.render_footer(f, Rect::new(area.x, area.y + area.height - 1, area.width, 1), &t);
        if self.modal.is_some() {
            self.render_modal(f, area, &t);
        }
        self.render_toasts(f, area, &t);
    }

    fn render_modules(&mut self, f: &mut Frame, area: Rect, t: &Theme) {
        let wide = self.width >= PREVIEW_MIN_WIDTH;
        let parts = if wide { 4 } else { 2 };
        let unit = area.width / parts;
        let modules = Rect { width: unit, ..area };
        let pkg_w = if wide { unit } else { area.width - unit };
        let pkg = Rect { x: area.x + unit, width: pkg_w, ..area };
        self.modules.render(f, modules, self.focus == Focus::Modules, t, t.bg);

        // Packages column: a border, its title, the list
        let rule = |f: &mut Frame, x: u16| {
            for y in area.y..area.y + area.height {
                f.render_widget(Paragraph::new("▏").style(t.rule()), Rect::new(x, y, 1, 1));
            }
        };
        rule(f, pkg.x);
        let title = Rect::new(pkg.x + 3, pkg.y, pkg.width.saturating_sub(4), 1);
        f.render_widget(Paragraph::new(Line::from(self.package_title())), title);
        let list = Rect::new(pkg.x + 1, pkg.y + 1, pkg.width.saturating_sub(1), pkg.height.saturating_sub(1));
        self.packages.render(f, list, self.focus == Focus::ModulePackages, t, t.bg);

        if !wide {
            self.preview_area = Rect::default();
            return;
        }
        let preview = Rect { x: pkg.x + pkg.width, width: area.width - 2 * unit, ..area };
        rule(f, preview.x);
        let inner = Rect::new(preview.x + 2, preview.y, preview.width.saturating_sub(3), preview.height);
        let first_show = self.preview_area.height == 0;
        self.preview_area = inner;
        if first_show && let Some(line) = self.preview_line {
            self.preview_scroll = line.saturating_sub(inner.height as usize / 2);
        }
        let max = self.preview.len().saturating_sub(inner.height as usize);
        self.preview_scroll = self.preview_scroll.min(max);
        let digits = self.preview.len().max(1).to_string().len();
        let lines: Vec<Line> = self
            .preview
            .iter()
            .enumerate()
            .skip(self.preview_scroll)
            .take(inner.height as usize)
            .map(|(n, code)| {
                let on = Some(n) == self.preview_line;
                let pointer = if on { span("❱ ", t.fg_of(t.error)) } else { plain("  ") };
                let number_style = if on { Style::default().add_modifier(Modifier::BOLD) } else { t.dim() };
                let mut spans = vec![pointer, span(format!("{:>digits$} ", n + 1), number_style)];
                spans.extend(code.iter().cloned());
                let line = Line::from(spans);
                if on && !t.ansi { line.style(Style::default().bg(t.mix(t.fg, 0.06))) } else { line }
            })
            .collect();
        f.render_widget(Paragraph::new(lines).style(t.base()), inner);
        // Scrollbar
        if self.preview.len() > inner.height as usize && inner.height > 0 {
            let (track, thumb) = t.scrollbar();
            let (h, total) = (inner.height as usize, self.preview.len());
            let size = (h * h).div_ceil(total).max(1);
            let start = (h - size) * self.preview_scroll / max.max(1);
            let x = preview.x + preview.width - 1;
            for i in 0..h {
                let on = i >= start && i < start + size;
                let style = if on { thumb.bg(t.bg) } else { track.bg(t.bg) };
                f.render_widget(Paragraph::new(if on { "▐" } else { " " }).style(style), Rect::new(x, inner.y + i as u16, 1, 1));
            }
        }
    }

    fn render_footer(&mut self, f: &mut Frame, area: Rect, t: &Theme) {
        self.footer_areas.clear();
        let keys: Vec<(&str, &str, Option<Action>)> = match &self.modal {
            Some(Modal::Confirm { .. }) => vec![("y", "Yes", None), ("n", "No", None)],
            Some(Modal::Generations { .. }) => vec![("esc", "Cancel", None), ("o", "Older", None), ("d", "Delete", None)],
            Some(_) => vec![("esc", "Cancel", None)],
            None => BINDINGS.iter().filter(|b| self.enabled(b.2)).map(|(k, d, a)| (*k, *d, Some(*a))).collect(),
        };
        let mut x = area.x + 1;
        let end = area.x + area.width;
        for (key, desc, action) in keys {
            let w = (key.width() + desc.width() + 3) as u16;
            if x + w > end {
                break;
            }
            let line = Line::from(vec![
                plain(" "),
                span(key, t.fg_of(t.primary).add_modifier(Modifier::BOLD)),
                plain(" "),
                span(desc, t.muted()),
                plain(" "),
            ]);
            let rect = Rect::new(x, area.y, w, 1);
            f.render_widget(Paragraph::new(line), rect);
            if let Some(action) = action {
                self.footer_areas.push((rect, action));
            }
            x += w;
        }
    }

    fn render_modal(&mut self, f: &mut Frame, area: Rect, t: &Theme) {
        // The screen behind, faded toward the background ($background 60%).
        let buf = f.buffer_mut();
        for y in area.y..area.y + area.height.saturating_sub(1) {
            for x in area.x..area.x + area.width {
                let cell = &mut buf[(x, y)];
                if t.ansi {
                    cell.modifier.insert(Modifier::DIM);
                } else {
                    cell.fg = t.mix_on(t.bg, 0.6, if cell.fg == Color::Reset { t.fg } else { cell.fg });
                    cell.bg = t.mix_on(t.bg, 0.6, if cell.bg == Color::Reset { t.bg } else { cell.bg });
                }
            }
        }
        let wide = matches!(self.modal, Some(Modal::Generations { .. } | Modal::Search { .. }));
        let width = if wide { area.width * 9 / 10 } else { 64.min(area.width.saturating_sub(2)) };
        let inner_w = width.saturating_sub(6); // border and padding 1 2
        let max_h = area.height * 8 / 10;
        let title_style = t.fg_of(t.primary).add_modifier(Modifier::BOLD);
        let hint = |text: &str| -> Spans {
            // "[b]y[/b] yes   [b]n[/b] no" style hints
            text.split("   ")
                .flat_map(|part| {
                    let (k, d) = part.split_once(' ').unwrap_or((part, ""));
                    [span(k.to_string(), Style::default().add_modifier(Modifier::BOLD)), plain(format!(" {d}   "))]
                })
                .collect()
        };
        let panel = t.panel;
        let modal = self.modal.as_mut().unwrap();
        let content_h: u16 = match modal {
            Modal::Prompt { title, .. } => wrapped_height(&[vec![plain(title.clone())]], inner_w) + 1 + 3,
            Modal::Confirm { question, .. } => wrapped_height(question, inner_w) + 2,
            Modal::Choose { list, .. } => 2 + list.len() as u16,
            Modal::Generations { .. } | Modal::Search { .. } => max_h.saturating_sub(4),
        };
        let height = (content_h + 4).min(max_h.max(6));
        let rect = Rect::new(area.x + (area.width - width) / 2, area.y + (area.height - height) / 2, width, height);
        f.render_widget(Clear, rect);
        let border = if t.ansi { t.fg_of(t.primary) } else { Style::default().fg(t.mix_on(t.primary, 0.6, panel)) };
        let block = Block::bordered()
            .border_type(BorderType::Rounded)
            .border_style(border.bg(panel))
            .style(Style::default().bg(panel).fg(t.fg));
        let inner = block.inner(rect);
        f.render_widget(block, rect);
        let inner = Rect::new(inner.x + 2, inner.y + 1, inner.width.saturating_sub(4), inner.height.saturating_sub(2));
        let mut y = inner.y;
        let text = |f: &mut Frame, lines: Vec<Spans>, style: Style, y: &mut u16| {
            let h = wrapped_height(&lines, inner.width).min(inner.y + inner.height - (*y).min(inner.y + inner.height));
            let lines: Vec<Line> = lines.into_iter().map(Line::from).collect();
            f.render_widget(Paragraph::new(lines).style(style).wrap(Wrap { trim: false }), Rect::new(inner.x, *y, inner.width, h));
            *y += h;
        };
        match modal {
            Modal::Prompt { title, input, .. } => {
                text(f, vec![vec![plain(title.clone())]], title_style, &mut y);
                y += 1;
                input.render(f, Rect::new(inner.x, y, inner.width, 3), true, t, panel);
            }
            Modal::Confirm { question, .. } => {
                text(f, question.clone(), title_style, &mut y);
                y += 1;
                text(f, vec![hint("y yes   n no")], t.muted(), &mut y);
            }
            Modal::Choose { title, list } => {
                text(f, vec![vec![plain(title.clone())]], title_style, &mut y);
                y += 1;
                let h = inner.y + inner.height - y;
                list.render(f, Rect::new(inner.x - 1, y, inner.width + 2, h), true, t, panel);
            }
            Modal::Generations { list, .. } => {
                text(f, vec![vec![plain("System generations to delete")]], title_style, &mut y);
                y += 1;
                let h = (inner.y + inner.height).saturating_sub(y + 2);
                list.render(f, Rect::new(inner.x - 1, y, inner.width + 2, h), true, t, panel);
                let hints = hint("space select   o select all older   d delete selected   esc cancel");
                f.render_widget(Paragraph::new(Line::from(hints)).style(t.muted()), Rect::new(inner.x, inner.y + inner.height - 1, inner.width, 1));
            }
            Modal::Search { title, input, status, list, on_results, .. } => {
                text(f, vec![vec![plain(title.clone())]], title_style, &mut y);
                y += 1;
                input.render(f, Rect::new(inner.x, y, inner.width, 3), !*on_results, t, panel);
                y += 4;
                f.render_widget(Paragraph::new(Line::from(status.clone())).style(t.muted()), Rect::new(inner.x, y, inner.width, 1));
                y += 2;
                let h = (inner.y + inner.height).saturating_sub(y);
                list.render(f, Rect::new(inner.x - 1, y, inner.width + 2, h), *on_results, t, panel);
            }
        }
    }

    fn render_toasts(&mut self, f: &mut Frame, area: Rect, t: &Theme) {
        let width = 60.min(area.width.saturating_sub(4));
        let mut bottom = area.y + area.height - 1; // above the footer
        for toast in self.toasts.iter().rev() {
            let color = match toast.severity {
                Severity::Info => t.success,
                Severity::Warning => t.warning,
                Severity::Error => t.error,
            };
            let mut lines: Vec<Spans> = Vec::new();
            if !toast.title.is_empty() {
                lines.push(vec![span(toast.title.clone(), t.fg_of(color).add_modifier(Modifier::BOLD))]);
            }
            lines.extend(toast.message.lines().map(|l| vec![plain(l.to_string())]));
            let inner_w = width.saturating_sub(4);
            let h = wrapped_height(&lines, inner_w) + 2;
            if bottom < area.y + h + 1 {
                break;
            }
            let rect = Rect::new(area.x + area.width - width - 2, bottom - h, width, h);
            f.render_widget(Clear, rect);
            let bg = t.panel;
            f.render_widget(Block::default().style(Style::default().bg(bg).fg(t.fg)), rect);
            for y in rect.y..rect.y + rect.height {
                f.render_widget(Paragraph::new("▌").style(Style::default().fg(color).bg(bg)), Rect::new(rect.x, y, 1, 1));
            }
            let lines: Vec<Line> = lines.into_iter().map(Line::from).collect();
            f.render_widget(
                Paragraph::new(lines).wrap(Wrap { trim: false }).style(Style::default().bg(bg).fg(t.fg)),
                Rect::new(rect.x + 2, rect.y + 1, inner_w, h - 2),
            );
            bottom -= h + 1;
        }
    }
}

/// Where to change a bind: Caelestia's kb* variables are overridden in
/// hypr-vars.lua (not in Caelestia's own variables.lua), the rest is edited
/// where it is written.
fn keybind_file(bind: &Bind) -> (PathBuf, Option<usize>) {
    if !bind.var.is_empty() {
        let vars = DOTFILES.join("config/caelestia/hypr-vars.lua");
        return (vars, (bind.source == "override").then_some(bind.line));
    }
    (bind.path.clone(), Some(bind.line))
}

/// One line of the Keybinds tab: combo, name, source, action.
fn keybind_row(t: &Theme, bind: &Bind) -> Spans {
    let combo = if !bind.combo.is_empty() {
        bind.combo.clone()
    } else if !bind.default.is_empty() {
        bind.default.clone()
    } else {
        "?".into()
    };
    let mark = if bind.conflict { span("!", t.fg_of(t.error)) } else { plain(" ") };
    let (text, source) = if bind.disabled() {
        (span(combo.clone(), t.dim().add_modifier(Modifier::CROSSED_OUT)), span("removed ", t.fg_of(t.error)))
    } else {
        let source = match bind.source {
            "default" => span("default ", t.dim()),
            "override" => span("override", t.fg_of(t.primary)),
            _ => span("user    ", t.fg_of(t.accent)),
        };
        (span(combo.clone(), Style::default().add_modifier(Modifier::BOLD)), source)
    };
    let mut row = vec![
        mark,
        plain(" "),
        text,
        plain(pad(&combo, 32, 2)),
        plain(bind.label.clone()),
        plain(pad(&bind.label, 40, 2)),
        source,
        plain("  "),
        span(bind.action.clone(), t.dim()),
    ];
    if bind.source == "override" && !bind.combo.is_empty() && !bind.default.is_empty() {
        let note = if keybinds::combo_key(&bind.combo) == keybinds::combo_key(&bind.default) {
            "  same as default".to_string()
        } else {
            format!("  was {}", bind.default)
        };
        row.push(span(note, t.dim().add_modifier(Modifier::ITALIC)));
    }
    row
}

fn shell_quote(s: &str) -> String {
    if !s.is_empty() && s.chars().all(|c| c.is_ascii_alphanumeric() || "@%+=:,./-_".contains(c)) {
        s.to_string()
    } else {
        format!("'{}'", s.replace('\'', r#"'"'"'"#))
    }
}

/// Run a command attached to the terminal, then wait for Enter.
///
/// With a theme, the terminal takes its colors meanwhile. The window may have
/// been closed (or hidden) meanwhile, so the result is also sent as a desktop
/// notification.
fn run_in_terminal(cmd: &[String], what: &str, theme: Option<&Theme>) {
    let mut out = io::stdout();
    if let Some(theme) = theme {
        let _ = write!(out, "{}", theme::terminal_palette(theme));
    }
    let _ = writeln!(out, "\n$ {}\n", cmd.join(" "));
    let _ = out.flush();
    let status = Command::new(&cmd[0]).args(&cmd[1..]).current_dir(&*DOTFILES).status();
    let (ok, status) = match status {
        Ok(s) if s.success() => (true, "done".to_string()),
        Ok(s) => (false, format!("failed (exit code {})", s.code().unwrap_or(-1))),
        Err(e) => (false, format!("failed ({e})")),
    };
    cfg::notify_desktop(&format!("nixcfg: {what} {status}"), &cmd.join(" "), !ok);
    let _ = write!(out, "\n{status}. Press Enter to go back to nixcfg...");
    let _ = out.flush();
    let _ = io::stdin().read_line(&mut String::new());
    if theme.is_some() {
        let _ = write!(out, "{}", theme::PALETTE_RESET);
        let _ = out.flush();
    }
}
