//! `nixcfg --dump`: everything nixcfg reads from the dotfiles, and the text of
//! every edit it can make, as JSON. compare.py computes the same with the
//! legacy Python version and diffs the two, to check they behave the same.
//! Nothing is written.

use serde_json::{Map, Value, json};

use crate::cfg::{self, CORE, DESKTOP_CORE, MODULES_DIR};
use crate::{hostfile, keybinds, modfile};

fn entry_json(e: &modfile::Entry) -> Value {
    json!([e.line, e.name, e.enabled, e.editable, e.comment])
}

pub fn dump() -> Value {
    let hosts = cfg::list_hosts();
    let modules = cfg::list_modules();
    let mut out = Map::new();
    out.insert("hosts".into(), json!(hosts));
    out.insert("modules".into(), json!(modules));

    let mut all_names: Vec<String> = vec![CORE.into()];
    let (mut state, mut names, mut sessions, mut desktops, mut imports, mut desktop_edits, mut defaults, mut blocks) =
        (Map::new(), Map::new(), Map::new(), Map::new(), Map::new(), Map::new(), Map::new(), Map::new());
    for host in &hosts {
        let enabled = cfg::load_state(host);
        let shown = cfg::module_names(host, &enabled);
        for n in &shown {
            if !all_names.contains(n) {
                all_names.push(n.clone());
            }
        }
        let text = cfg::read(&cfg::host_path(host));
        state.insert(host.clone(), json!(enabled));
        names.insert(host.clone(), json!(shown));
        sessions.insert(host.clone(), json!(hostfile::default_session(&text)));
        desktops.insert(host.clone(), json!(hostfile::desktops(&text)));
        blocks.insert(host.clone(), json!(hostfile::add_packages_block(&text)));

        // The host file after turning each of its own modules on or off.
        let own: Vec<String> = enabled.iter().filter(|n| cfg::group_core(n).is_none()).cloned().collect();
        let mut edits = Map::new();
        for name in shown.iter().filter(|n| cfg::group_core(n).is_none() && !cfg::is_pinned(n)) {
            let chosen: Vec<String> = if own.contains(name) {
                own.iter().filter(|n| *n != name).cloned().collect()
            } else {
                own.iter().cloned().chain([name.clone()]).collect()
            };
            let path = cfg::host_path(host);
            let result = hostfile::update(&text, path.parent().unwrap(), &MODULES_DIR, &chosen, |n| {
                cfg::module_path(n).exists()
            }, cfg::display_key);
            edits.insert(name.clone(), json!(result.ok()));
        }
        imports.insert(host.clone(), Value::Object(edits));

        // The host file after turning each desktop on or off, and as the default.
        let known: Vec<String> = cfg::list_desktops().iter().map(|n| cfg::desktop_name(n).to_string()).collect();
        let on = hostfile::desktops(&text);
        let (mut edits, mut default) = (Map::new(), Map::new());
        for d in &known {
            let chosen: Vec<String> =
                if on.contains(d) { on.iter().filter(|n| *n != d).cloned().collect() } else { on.iter().cloned().chain([d.clone()]).collect() };
            edits.insert(d.clone(), json!(hostfile::update_desktops(&text, &chosen, &known)));
            default.insert(d.clone(), json!(hostfile::set_default_session(&text, d).ok()));
        }
        edits.insert("(none)".into(), json!(hostfile::update_desktops(&text, &[], &known)));
        desktop_edits.insert(host.clone(), Value::Object(edits));
        defaults.insert(host.clone(), Value::Object(default));
    }
    out.insert("state".into(), Value::Object(state));
    out.insert("names".into(), Value::Object(names));
    out.insert("default_session".into(), Value::Object(sessions));
    out.insert("desktops".into(), Value::Object(desktops));
    out.insert("add_packages_block".into(), Value::Object(blocks));
    out.insert("import_edits".into(), Value::Object(imports));
    out.insert("desktop_edits".into(), Value::Object(desktop_edits));
    out.insert("default_session_edits".into(), Value::Object(defaults));

    // Per module: how it is grouped, its packages, and the file after each edit.
    let (mut info, mut entries, mut edits) = (Map::new(), Map::new(), Map::new());
    for name in &all_names {
        info.insert(
            name.clone(),
            json!({
                "display_key": cfg::display_key(name),
                "group_core": cfg::group_core(name),
                "is_group": cfg::is_group(name),
                "is_pinned": cfg::is_pinned(name),
            }),
        );
        let text = cfg::read(&cfg::module_path(name));
        let list = modfile::entries(&text);
        entries.insert(name.clone(), json!(list.iter().map(entry_json).collect::<Vec<_>>()));
        let mut e = Map::new();
        for entry in list.iter().filter(|e| e.editable) {
            e.insert(format!("toggle:{}", entry.line), json!(modfile::toggle(&text, entry)));
            e.insert(format!("remove:{}", entry.line), json!(modfile::remove(&text, entry)));
        }
        e.insert("add".into(), json!(modfile::add(&text, "nixcfg-test", "  # A  test  package ")));
        e.insert("add-bare".into(), json!(modfile::add(&text, "nixcfg-test", "")));
        edits.insert(name.clone(), Value::Object(e));
    }
    out.insert("module_info".into(), Value::Object(info));
    out.insert("entries".into(), Value::Object(entries));
    out.insert("package_edits".into(), Value::Object(edits));

    // Group cores after turning each of their submodules on or off.
    let mut cores = Map::new();
    for core in modules.iter().filter(|n| cfg::is_group(n) && *n != DESKTOP_CORE) {
        let subs = cfg::group_subs(core);
        let mut e = Map::new();
        for sub in modules.iter().filter(|n| cfg::group_core(n).as_deref() == Some(core)) {
            let chosen: Vec<String> =
                if subs.contains(sub) { subs.iter().filter(|n| *n != sub).cloned().collect() } else { subs.iter().cloned().chain([sub.clone()]).collect() };
            e.insert(sub.clone(), json!(cfg::core_text(core, &chosen).ok()));
        }
        cores.insert(core.clone(), Value::Object(e));
    }
    out.insert("core_edits".into(), Value::Object(cores));

    let binds: Vec<Value> = keybinds::load(&cfg::DOTFILES)
        .iter()
        .map(|b| {
            json!({
                "combo": b.combo, "label": b.label, "action": b.action, "source": b.source,
                "path": b.path.to_string_lossy(), "line": b.line, "var": b.var, "default": b.default,
                "section": b.section, "flags": b.flags, "conflict": b.conflict,
            })
        })
        .collect();
    out.insert("keybinds".into(), json!(binds));
    Value::Object(out)
}
