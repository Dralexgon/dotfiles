//! The few widgets nixcfg needs, drawn the way the Textual version drew them:
//! option lists (one row per item, a highlighted row), selection lists (the
//! same with a ● toggle per row) and a one-line text input.

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use ratatui::Frame;
use ratatui::layout::{Position, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, Paragraph};
use unicode_width::UnicodeWidthStr;

use crate::theme::Theme;

pub type Spans = Vec<Span<'static>>;

pub fn span(text: impl Into<String>, style: Style) -> Span<'static> {
    Span::styled(text.into(), style)
}

pub fn plain(text: impl Into<String>) -> Span<'static> {
    Span::raw(text.into())
}

/// Rich's [dim] over a whole label: every span's color blended toward the
/// background.
pub fn dim_spans(theme: &Theme, spans: Spans) -> Spans {
    spans
        .into_iter()
        .map(|s| {
            let style = if theme.ansi {
                s.style.add_modifier(Modifier::DIM)
            } else {
                s.style.fg(theme.mix(s.style.fg.unwrap_or(theme.fg), 0.5))
            };
            Span::styled(s.content, style)
        })
        .collect()
}

/// Cut a label to `width` columns, ending it with "…" like Textual does.
pub fn truncate_spans(spans: Spans, width: usize) -> Spans {
    if spans_width(&spans) <= width {
        return spans;
    }
    let mut out = Vec::new();
    let mut used = 0;
    let room = width.saturating_sub(1);
    for s in spans {
        let w = s.content.width();
        if used + w <= room {
            used += w;
            out.push(s);
            continue;
        }
        let mut text = String::new();
        for c in s.content.chars() {
            let cw = unicode_width::UnicodeWidthChar::width(c).unwrap_or(0);
            if used + cw > room {
                break;
            }
            used += cw;
            text.push(c);
        }
        let style = s.style;
        out.push(Span::styled(text, style));
        out.push(Span::styled("…", style));
        return out;
    }
    out
}

pub fn spans_width(spans: &[Span]) -> usize {
    spans.iter().map(|s| s.content.width()).sum()
}

#[derive(Clone)]
pub struct Row {
    pub id: String,
    pub label: Spans,
    /// Some for a selection list's rows (its ● toggle), None for an option list's.
    pub selected: Option<bool>,
    /// Can't be highlighted (headings) or toggled (read-only packages).
    pub disabled: bool,
}

impl Row {
    pub fn option(id: impl Into<String>, label: Spans) -> Self {
        Row { id: id.into(), label, selected: None, disabled: false }
    }
    pub fn selection(id: impl Into<String>, label: Spans, selected: bool) -> Self {
        Row { id: id.into(), label, selected: Some(selected), disabled: false }
    }
    pub fn disabled(mut self, disabled: bool) -> Self {
        self.disabled = disabled;
        self
    }
}

#[derive(Default)]
pub struct List {
    pub rows: Vec<Row>,
    pub highlighted: Option<usize>,
    pub offset: usize,
    /// Where it was last drawn (for the mouse and page keys).
    pub area: Rect,
}

impl List {
    pub fn set_rows(&mut self, rows: Vec<Row>) {
        self.rows = rows;
        self.highlighted = None;
    }

    pub fn len(&self) -> usize {
        self.rows.len()
    }

    pub fn current(&self) -> Option<&Row> {
        self.highlighted.and_then(|i| self.rows.get(i))
    }

    pub fn current_id(&self) -> Option<&str> {
        self.current().map(|r| r.id.as_str())
    }

    pub fn index_of(&self, id: &str) -> Option<usize> {
        self.rows.iter().position(|r| r.id == id)
    }

    /// Highlight a row by id; false when it is not there.
    pub fn select_id(&mut self, id: &str) -> bool {
        match self.index_of(id) {
            Some(i) => {
                self.highlighted = Some(i);
                true
            }
            None => false,
        }
    }

    /// The first row that is not disabled.
    pub fn first(&mut self) {
        self.highlighted = self.rows.iter().position(|r| !r.disabled);
    }

    fn last(&mut self) {
        self.highlighted = self.rows.iter().rposition(|r| !r.disabled);
    }

    /// Move the highlight, skipping disabled rows. Returns whether it changed.
    pub fn step(&mut self, delta: isize) -> bool {
        let before = self.highlighted;
        let Some(current) = self.highlighted else {
            if delta > 0 { self.first() } else { self.last() }
            return self.highlighted != before;
        };
        let mut i = current as isize;
        let mut target = None;
        loop {
            i += delta.signum();
            if i < 0 || i >= self.rows.len() as isize {
                break;
            }
            if !self.rows[i as usize].disabled {
                target = Some(i as usize);
                if (i - current as isize).abs() >= delta.abs() {
                    break;
                }
            }
        }
        if let Some(t) = target {
            self.highlighted = Some(t);
        }
        self.highlighted != before
    }

    /// Navigation keys; returns Some(changed) when the key was one of them.
    pub fn nav_key(&mut self, key: &KeyEvent) -> Option<bool> {
        let page = self.area.height.max(2) as isize - 1;
        let before = self.highlighted;
        match key.code {
            KeyCode::Up | KeyCode::Char('k') => Some(self.step(-1)),
            KeyCode::Down | KeyCode::Char('j') => Some(self.step(1)),
            KeyCode::PageUp => Some(self.step(-page)),
            KeyCode::PageDown => Some(self.step(page)),
            KeyCode::Home => {
                self.first();
                Some(self.highlighted != before)
            }
            KeyCode::End => {
                self.last();
                Some(self.highlighted != before)
            }
            _ => None,
        }
    }

    /// The row under a mouse position, if any.
    pub fn row_at(&self, col: u16, row: u16) -> Option<usize> {
        if !self.area.contains(Position::new(col, row)) {
            return None;
        }
        let i = self.offset + (row - self.area.y) as usize;
        (i < self.rows.len()).then_some(i)
    }

    pub fn scroll(&mut self, delta: isize) {
        let max = self.rows.len().saturating_sub(self.area.height as usize);
        self.offset = (self.offset as isize + delta).clamp(0, max as isize) as usize;
    }

    /// Keep the highlighted row on screen.
    fn follow(&mut self, height: usize) {
        if let Some(h) = self.highlighted {
            if h < self.offset {
                self.offset = h;
            } else if h >= self.offset + height {
                self.offset = h + 1 - height;
            }
        }
        let max = self.rows.len().saturating_sub(height);
        self.offset = self.offset.min(max);
    }

    /// Draw it: padding 0 1, each row padded 0 1, a scrollbar when it overflows.
    pub fn render(&mut self, f: &mut Frame, area: Rect, focused: bool, theme: &Theme, bg: ratatui::style::Color) {
        self.area = area;
        if area.width < 3 || area.height == 0 {
            return;
        }
        let height = area.height as usize;
        let following = self.highlighted;
        if following.is_some() {
            self.follow(height);
        } else {
            let max = self.rows.len().saturating_sub(height);
            self.offset = self.offset.min(max);
        }
        let overflow = self.rows.len() > height;
        let inner = Rect { x: area.x + 1, width: area.width.saturating_sub(2), ..area };
        let base = Style::default().fg(theme.fg).bg(bg);
        for (n, row) in self.rows.iter().enumerate().skip(self.offset).take(height) {
            let y = area.y + (n - self.offset) as u16;
            let line_area = Rect { y, height: 1, ..inner };
            let highlighted = Some(n) == self.highlighted;
            let row_style = if highlighted { base.patch(theme.highlight(focused)) } else { base };
            let mut spans: Spans = vec![plain(" ")];
            if let Some(selected) = row.selected {
                let dot = if selected {
                    Style::default().fg(theme.primary).add_modifier(Modifier::BOLD)
                } else if theme.ansi {
                    Style::default().add_modifier(Modifier::DIM)
                } else {
                    Style::default().fg(theme.mix(theme.fg, 0.25))
                };
                spans.push(span(" ● ", dot));
                spans.push(plain(" "));
            }
            let label = if row.disabled && row.selected.is_some() { dim_spans(theme, row.label.clone()) } else { row.label.clone() };
            let room = (inner.width as usize).saturating_sub(spans_width(&spans) + 1 + overflow as usize);
            spans.extend(truncate_spans(label, room));
            // Spans without a color of their own take the row's (primary when focused).
            let line = Line::from(spans).style(row_style);
            f.render_widget(Paragraph::new(line).style(row_style), line_area);
        }
        if overflow {
            let (track, thumb) = theme.scrollbar();
            let x = area.x + area.width - 1;
            let total = self.rows.len();
            let size = ((height * height) as f32 / total as f32).ceil().max(1.0) as usize;
            let max_offset = total - height;
            let start = ((height - size) * self.offset).checked_div(max_offset).unwrap_or(0);
            for i in 0..height {
                let on = i >= start && i < start + size;
                let cell = Rect { x, y: area.y + i as u16, width: 1, height: 1 };
                let style = if on { thumb.bg(bg) } else { track.bg(bg) };
                f.render_widget(Paragraph::new(if on { "▐" } else { " " }).style(style), cell);
            }
        }
    }
}

#[derive(Default)]
pub struct Input {
    pub value: String,
    cursor: usize, // in chars
    pub placeholder: String,
    pub area: Rect,
}

impl Input {
    pub fn new(placeholder: &str) -> Self {
        Input { placeholder: placeholder.into(), ..Default::default() }
    }

    fn byte(&self, chars: usize) -> usize {
        self.value.char_indices().nth(chars).map_or(self.value.len(), |(i, _)| i)
    }

    /// Edit keys; returns Some(changed value) when the key was one of them.
    pub fn key(&mut self, key: &KeyEvent) -> Option<bool> {
        let len = self.value.chars().count();
        let ctrl = key.modifiers.contains(KeyModifiers::CONTROL);
        match key.code {
            KeyCode::Char('u') if ctrl => {
                let at = self.byte(self.cursor);
                self.value.replace_range(..at, "");
                self.cursor = 0;
                Some(true)
            }
            KeyCode::Char('w') if ctrl => {
                let before: Vec<char> = self.value.chars().take(self.cursor).collect();
                let mut start = before.len();
                while start > 0 && before[start - 1] == ' ' {
                    start -= 1;
                }
                while start > 0 && before[start - 1] != ' ' {
                    start -= 1;
                }
                let (a, b) = (self.byte(start), self.byte(self.cursor));
                self.value.replace_range(a..b, "");
                self.cursor = start;
                Some(true)
            }
            KeyCode::Char('a') if ctrl => {
                self.cursor = 0;
                Some(false)
            }
            KeyCode::Char('e') if ctrl => {
                self.cursor = len;
                Some(false)
            }
            KeyCode::Char(c) if !ctrl => {
                let at = self.byte(self.cursor);
                self.value.insert(at, c);
                self.cursor += 1;
                Some(true)
            }
            KeyCode::Backspace if self.cursor > 0 => {
                let (a, b) = (self.byte(self.cursor - 1), self.byte(self.cursor));
                self.value.replace_range(a..b, "");
                self.cursor -= 1;
                Some(true)
            }
            KeyCode::Delete if self.cursor < len => {
                let (a, b) = (self.byte(self.cursor), self.byte(self.cursor + 1));
                self.value.replace_range(a..b, "");
                Some(true)
            }
            KeyCode::Backspace | KeyCode::Delete => Some(false),
            KeyCode::Left => {
                self.cursor = self.cursor.saturating_sub(1);
                Some(false)
            }
            KeyCode::Right => {
                self.cursor = (self.cursor + 1).min(len);
                Some(false)
            }
            KeyCode::Home => {
                self.cursor = 0;
                Some(false)
            }
            KeyCode::End => {
                self.cursor = len;
                Some(false)
            }
            _ => None,
        }
    }

    /// Draw it in a rounded border (3 rows high).
    pub fn render(&mut self, f: &mut Frame, area: Rect, focused: bool, theme: &Theme, bg: ratatui::style::Color) {
        self.area = area;
        let border = if focused {
            Style::default().fg(theme.primary)
        } else if theme.ansi {
            Style::default().add_modifier(Modifier::DIM)
        } else {
            Style::default().fg(theme.mix(theme.fg, 0.2))
        };
        let block = Block::bordered().border_type(BorderType::Rounded).border_style(border.bg(bg)).style(Style::default().bg(bg));
        let inner = block.inner(area);
        f.render_widget(block, area);
        let inner = Rect { x: inner.x + 1, width: inner.width.saturating_sub(2), ..inner };
        let style = Style::default().fg(theme.fg).bg(bg);
        if self.value.is_empty() {
            f.render_widget(Paragraph::new(span(self.placeholder.clone(), theme.muted())).style(style), inner);
        } else {
            // Scroll so the cursor stays visible.
            let before: String = self.value.chars().take(self.cursor).collect();
            let skip = before.width().saturating_sub(inner.width.saturating_sub(1) as usize);
            let shown: String = self.value.chars().skip(skip).collect();
            f.render_widget(Paragraph::new(shown).style(style), inner);
        }
        if focused {
            let before: String = self.value.chars().take(self.cursor).collect();
            let x = (before.width() as u16).min(inner.width.saturating_sub(1));
            f.set_cursor_position(Position::new(inner.x + x, inner.y));
        }
    }

    pub fn contains(&self, col: u16, row: u16) -> bool {
        self.area.contains(Position::new(col, row))
    }
}

/// How many rows `spans` take when wrapped at `width`.
pub fn wrapped_height(lines: &[Spans], width: u16) -> u16 {
    let width = width.max(1) as usize;
    lines.iter().map(|l| spans_width(l).max(1).div_ceil(width) as u16).sum()
}
