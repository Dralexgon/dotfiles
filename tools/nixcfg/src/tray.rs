//! A tray icon for nixcfg (StatusNotifierItem over D-Bus, like Discord's).
//!
//! It shows while nixcfg runs in the background: clicking it opens the window,
//! and its menu (on hover in Caelestia) can open or quit nixcfg. ksni runs it
//! in its own thread, so it keeps answering while the app is suspended for an
//! update or rebuild, and registers again when the tray restarts.

use std::sync::mpsc::Sender;

use ksni::blocking::{Handle, TrayMethods};
use ksni::menu::StandardItem;
use ksni::{Category, MenuItem, ToolTip};

const ICON: &str = "nix-snowflake";

pub struct Tray {
    busy: String, // what is running, shown in the tooltip and the menu
    events: Sender<crate::app::Msg>,
}

impl ksni::Tray for Tray {
    fn id(&self) -> String {
        "nixcfg".into()
    }
    fn title(&self) -> String {
        "nixcfg".into()
    }
    fn category(&self) -> Category {
        Category::SystemServices
    }
    fn icon_name(&self) -> String {
        ICON.into()
    }
    fn tool_tip(&self) -> ToolTip {
        ToolTip {
            icon_name: ICON.into(),
            icon_pixmap: vec![],
            title: "nixcfg".into(),
            description: if self.busy.is_empty() { "Running in the background".into() } else { self.busy.clone() },
        }
    }
    fn activate(&mut self, _x: i32, _y: i32) {
        crate::window::show();
    }
    fn secondary_activate(&mut self, _x: i32, _y: i32) {
        crate::window::show();
    }
    fn menu(&self) -> Vec<MenuItem<Self>> {
        let busy = !self.busy.is_empty();
        vec![
            StandardItem {
                label: "Open nixcfg".into(),
                activate: Box::new(|_: &mut Self| crate::window::show()),
                ..Default::default()
            }
            .into(),
            StandardItem { label: self.busy.clone(), enabled: false, visible: busy, ..Default::default() }.into(),
            MenuItem::Separator,
            // Quitting would kill the running command: wait for it.
            StandardItem {
                label: "Quit nixcfg".into(),
                enabled: !busy,
                activate: Box::new(|this: &mut Self| {
                    if this.busy.is_empty() {
                        let _ = this.events.send(crate::app::Msg::Quit);
                    }
                }),
                ..Default::default()
            }
            .into(),
        ]
    }
}

pub struct TrayHandle(Handle<Tray>);

impl TrayHandle {
    /// Show the icon; None without a session bus or a tray to show it in.
    pub fn start(events: Sender<crate::app::Msg>) -> Option<Self> {
        Tray { busy: String::new(), events }.assume_sni_available(true).spawn().ok().map(TrayHandle)
    }

    /// Safe to call from any thread.
    pub fn set_busy(&self, text: &str) {
        let text = text.to_string();
        self.0.update(move |t| t.busy = text);
    }
}
