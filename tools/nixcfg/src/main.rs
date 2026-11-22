//! nixcfg: a TUI to enable/disable/add/remove modules and packages of the
//! NixOS hosts in ~/dotfiles.
//!
//! Everything stays Nix code and is toggled by commenting lines out, the way
//! you would by hand: modules in the `imports` of each host's
//! configuration.nix and submodules in the `imports` of their group's core.nix
//! (see hostfile.rs), packages in environment.systemPackages lists (see
//! modfile.rs). Every module change is checked with Nix and reverted if it
//! breaks the config.
//!
//! This is the Rust version; the original Python (Textual) one is kept in
//! legacy/ (nixcfg-legacy).

mod app;
mod cfg;
mod dump;
mod hostfile;
mod keybinds;
mod modfile;
mod nixhl;
mod text;
mod theme;
mod tray;
mod widgets;
mod window;

use std::io::Write;

fn main() {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    if args.iter().any(|a| a == "--dump") {
        // Ignore a closed pipe (nixcfg --dump | head).
        let _ = writeln!(std::io::stdout(), "{}", serde_json::to_string_pretty(&dump::dump()).unwrap());
        return;
    }
    if args.iter().any(|a| a == "-h" || a == "--help") {
        println!("nixcfg [--foreground]: toggle the modules and packages of the NixOS hosts in ~/dotfiles");
        println!("  --foreground  run in this terminal, without the background tmux session");
        println!("  --dump        print what nixcfg reads and every edit it can make, as JSON");
        return;
    }
    if cfg::list_hosts().is_empty() {
        eprintln!(
            "No nixos/hosts/*/configuration.nix found in {} (set NIXCFG_DOTFILES).",
            cfg::DOTFILES.display()
        );
        std::process::exit(1);
    }
    window::attach_or_start(&mut args);
    if let Err(e) = app::run() {
        eprintln!("nixcfg: {e}");
        std::process::exit(1);
    }
}
