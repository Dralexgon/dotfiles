#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Optional private companion repo (Dralexgon/dotfiles-private): files with personal info
PRIVATE_DIR="${DOTFILES_PRIVATE_DIR:-$HOME/dotfiles-private}"
HOSTS_DIR="$DOTFILES_DIR/nixos/hosts"
MODULES_DIR="$DOTFILES_DIR/nixos/modules"

MODE="tui"
WANT_CAELESTIA=0
WANT_LIFE_MANAGER=0
ASK_USER=1
CREATED_USER=""
HARDWARE_CONFIG=""

usage() {
	cat <<EOF
Usage: $(basename -- "$0") [-t|--tui] [-i|--input] [-g|--gui] [--current-user] [--hardware-config FILE] [-h|--help]

Interactive installer for these dotfiles.

Steps:
  0. Target user: install for the current user, or create a new user (for
     example to try these dotfiles safely). A new user gets a copy of this
     repo in its home, the installer re-runs as that user, and the command
     to delete it is printed at the end.
  1. Caelestia (optional): asks whether to install Caelestia. If yes, the
     caelestia desktop is preselected for a new host, and 'caelestia install'
     is run with the components you pick.
  2. Projects (optional): clones the projects that live in their own
     repos (nova -> ~/dev/ai/nova, life-manager -> ~/dev/apps/life-manager),
     where these dotfiles expect them. life-manager preselects its module.
  3. NixOS host setup (optional): creates nixos/hosts/<hostname>/ with the
     hostname, desktops, modules and tools (from tools/) you choose (and the
     target user) and the NixOS release this machine was installed with
     (system.stateVersion), generates hardware-configuration.nix, and git-adds
     the host directory (flake.nix picks up every host in nixos/hosts/).
  4. Dotfile configuration: symlinks selected config groups from config/
     into \$HOME (bash -> ~/.bashrc, git -> ~/.gitconfig*, ssh -> ~/.ssh/config,
     clang-format -> ~/.clang-format,
     others -> ~/.config/<name>), offering
     to back up existing files first.

Options:
  -t, --tui     Pick choices with the arrow keys (default).
  -i, --input   Answer by typing (y/n, numbers). Used automatically when
                not running in a terminal.
  -g, --gui     A window instead of the terminal (GTK, tools/installer-gui).
                Started through 'nix run' when installer-gui isn't installed.
  --current-user
                Install for the current user without asking.
  --hardware-config FILE
                Use FILE as hardware-configuration.nix instead of running
                'sudo nixos-generate-config' (used for a new user, so it
                does not need sudo during the install).
  -h, --help    Show this help and exit.

TUI keys: Up/Down or k/j to move, Space to toggle, a to toggle all,
Enter to confirm, q to quit.
EOF
}

# ---------------------------------------------------------------------------
# Prompts. Every prompt works in every mode; results are returned in globals
# (ANSWER, SELECTED) so the TUI can draw on the terminal without a subshell.
# ---------------------------------------------------------------------------

# GUI mode (--gui-backend, run by tools/installer-gui): a prompt is one line on
# stdout, "\x1e" then a JSON object, and the window writes the answer back on
# stdin as one line. Everything else on stdout / stderr goes to its log.
json_str() {
	local s="$1"
	s="${s//\\/\\\\}"
	s="${s//\"/\\\"}"
	s="${s//$'\n'/\\n}"
	s="${s//$'\t'/\\t}"
	s="${s//$'\r'/}"
	printf '"%s"' "$s"
}

json_list() {
	local first=1 item
	printf '['
	for item in "$@"; do
		(( first )) || printf ','
		first=0
		json_str "$item"
	done
	printf ']'
}

# gui_ask JSON -> ANSWER
gui_ask() {
	printf '\x1e%s\n' "$1"
	if ! IFS= read -r ANSWER; then
		printf 'The installer window was closed.\n' >&2
		exit 1
	fi
}

tui_cleanup() {
	printf '\e[?25h' >&2
}

on_exit() {
	[[ "$MODE" == "tui" ]] && tui_cleanup
	if [[ -n "$CREATED_USER" ]]; then
		printf '\nUser "%s" was created. If you want to delete it and its home later, run:\n' "$CREATED_USER"
		printf '  sudo userdel -r %s\n' "$CREATED_USER"
	fi
}

read_key() {
	local key rest
	IFS= read -rsn1 key
	if [[ "$key" == $'\e' ]]; then
		IFS= read -rsn2 -t 0.05 rest || true
		key+="$rest"
	fi
	case "$key" in
		$'\e[A' | k) KEY="up" ;;
		$'\e[B' | j) KEY="down" ;;
		' ') KEY="space" ;;
		'') KEY="enter" ;;
		a | A) KEY="all" ;;
		q | Q) KEY="quit" ;;
		*) KEY="other" ;;
	esac
}

# ask_text PROMPT [DEFAULT] [PATTERN] -> ANSWER
# PATTERN (a regex) only lets the GUI refuse invalid answers early: callers
# still check the answer.
ask_text() {
	local prompt="$1"
	local default_answer="${2:-}"
	local suffix=""

	if [[ "$MODE" == "gui" ]]; then
		gui_ask "{\"type\":\"text\",\"prompt\":$(json_str "$prompt"),\"default\":$(json_str "$default_answer"),\"pattern\":$(json_str "${3:-}")}"
		return
	fi

	[[ -n "$default_answer" ]] && suffix=" [$default_answer]"
	read -r -p "$prompt$suffix: " ANSWER
	ANSWER="${ANSWER:-$default_answer}"
}

# select_one TITLE DEFAULT_INDEX OPTION... -> SELECTED (index)
select_one() {
	local title="$1"
	local current="$2"
	shift 2
	local -a options=("$@")
	local i answer

	if [[ "$MODE" == "gui" ]]; then
		gui_ask "{\"type\":\"one\",\"title\":$(json_str "$title"),\"default\":$current,\"options\":$(json_list "${options[@]}")}"
		if [[ "$ANSWER" =~ ^[0-9]+$ ]] && (( ANSWER < ${#options[@]} )); then
			SELECTED="$ANSWER"
		else
			SELECTED="$current"
		fi
		return
	fi

	if [[ "$MODE" == "input" ]]; then
		printf '%s\n' "$title"
		for i in "${!options[@]}"; do
			printf '  %d) %s\n' "$((i + 1))" "${options[$i]}"
		done
		while true; do
			read -r -p "Choice [$((current + 1))]: " answer
			answer="${answer:-$((current + 1))}"
			if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= ${#options[@]} )); then
				SELECTED=$((answer - 1))
				return
			fi
			printf 'Please enter a number between 1 and %d.\n' "${#options[@]}" >&2
		done
	fi

	printf '\e[?25l' >&2
	printf '%s\n' "$title" >&2
	while true; do
		for i in "${!options[@]}"; do
			if (( i == current )); then
				printf '\e[2K  \e[1;36m> %s\e[0m\n' "${options[$i]}" >&2
			else
				printf '\e[2K    %s\n' "${options[$i]}" >&2
			fi
		done
		read_key
		case "$KEY" in
			up) current=$(( (current - 1 + ${#options[@]}) % ${#options[@]} )) ;;
			down) current=$(( (current + 1) % ${#options[@]} )) ;;
			enter) break ;;
			quit) tui_cleanup; printf 'Aborted.\n' >&2; exit 1 ;;
		esac
		printf '\e[%dA' "${#options[@]}" >&2
	done
	tui_cleanup
	SELECTED="$current"
}

# ask_yes_no PROMPT DEFAULT(y|n) -> exit status 0 for yes
ask_yes_no() {
	local prompt="$1"
	local default_answer="$2"
	local answer hint="[y/N]"

	if [[ "$MODE" == "gui" ]]; then
		gui_ask "{\"type\":\"yesno\",\"prompt\":$(json_str "$prompt"),\"default\":$(json_str "$default_answer")}"
		[[ "$ANSWER" == "y" ]]
		return
	fi

	if [[ "$MODE" == "input" ]]; then
		[[ "$default_answer" == "y" ]] && hint="[Y/n]"
		read -r -p "$prompt $hint " answer
		answer="${answer:-$default_answer}"
		[[ "$answer" =~ ^[Yy] ]]
		return
	fi

	if [[ "$default_answer" == "y" ]]; then
		select_one "$prompt" 0 "Yes" "No"
	else
		select_one "$prompt" 1 "Yes" "No"
	fi
	(( SELECTED == 0 ))
}

# select_many TITLE OPTIONS_ARRAY_NAME CHECKED_ARRAY_NAME
# CHECKED holds 0/1 per option on input and the user's choice on output.
select_many() {
	local title="$1"
	local -n opts="$2"
	local -n checked="$3"
	local count="${#opts[@]}"
	local current=0 top=0 height i mark answer all

	(( count == 0 )) && return

	if [[ "$MODE" == "gui" ]]; then
		gui_ask "{\"type\":\"many\",\"title\":$(json_str "$title"),\"options\":$(json_list "${opts[@]}"),\"checked\":[$(IFS=,; printf '%s' "${checked[*]}")]}"
		# the answer: one 0 or 1 per option
		read -ra answer <<<"$ANSWER"
		for i in "${!opts[@]}"; do
			[[ "${answer[i]:-}" == 1 ]] && checked[i]=1 || checked[i]=0
		done
		return
	fi

	if [[ "$MODE" == "input" ]]; then
		printf '%s\n' "$title"
		for i in "${!opts[@]}"; do
			mark=" "
			(( checked[i] )) && mark="x"
			printf '  %2d) [%s] %s\n' "$((i + 1))" "$mark" "${opts[$i]}"
		done
		read -r -p "Numbers separated by spaces (Enter keeps [x], '-' selects none): " answer
		[[ -z "$answer" ]] && return
		for i in "${!opts[@]}"; do
			checked[i]=0
		done
		[[ "$answer" == "-" ]] && return
		for i in $answer; do
			if [[ "$i" =~ ^[0-9]+$ ]] && (( i >= 1 && i <= count )); then
				checked[i - 1]=1
			else
				printf 'Ignoring invalid selection: %s\n' "$i" >&2
			fi
		done
		return
	fi

	height=$(( $(tput lines 2>/dev/null || echo 24) - 4 ))
	(( height < 3 )) && height=3
	(( height > count )) && height="$count"

	printf '\e[?25l' >&2
	printf '%s \e[2m(Space toggle, a all, Enter confirm)\e[0m\n' "$title" >&2
	while true; do
		if (( current < top )); then
			top="$current"
		elif (( current >= top + height )); then
			top=$(( current - height + 1 ))
		fi
		for (( i = top; i < top + height; i++ )); do
			mark=" "
			(( checked[i] )) && mark="x"
			if (( i == current )); then
				printf '\e[2K  \e[1;36m> [%s] %s\e[0m\n' "$mark" "${opts[$i]}" >&2
			else
				printf '\e[2K    [%s] %s\n' "$mark" "${opts[$i]}" >&2
			fi
		done
		if (( height < count )); then
			printf '\e[2K    \e[2m(%d/%d)\e[0m\n' "$((current + 1))" "$count" >&2
		fi
		read_key
		case "$KEY" in
			up) current=$(( (current - 1 + count) % count )) ;;
			down) current=$(( (current + 1) % count )) ;;
			space) checked[current]=$(( 1 - checked[current] )) ;;
			all)
				all=0
				for i in "${!opts[@]}"; do
					(( checked[i] )) || all=1
				done
				for i in "${!opts[@]}"; do
					checked[i]="$all"
				done
				;;
			enter) break ;;
			quit) tui_cleanup; printf 'Aborted.\n' >&2; exit 1 ;;
		esac
		printf '\e[%dA' "$(( height + (height < count ? 1 : 0) ))" >&2
	done
	tui_cleanup
}

# ---------------------------------------------------------------------------
# Install steps
# ---------------------------------------------------------------------------

valid_name() {
	[[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]
}

# Optionally create a new user and run the whole install as that user, on a
# copy of this repo, so the current user's dotfiles stay untouched.
choose_user() {
	local name home password confirm status=0

	select_one "Install for:" 0 "Current user ($USER)" "A new user (e.g. to try these dotfiles safely)"
	(( SELECTED == 0 )) && return

	ask_text "New username" "dotfiles-test" '^[a-zA-Z0-9_-]+$'
	name="$ANSWER"
	if ! valid_name "$name"; then
		printf 'Usernames may contain only letters, numbers, underscores, and hyphens.\n' >&2
		exit 1
	fi
	if id -- "$name" >/dev/null 2>&1; then
		printf 'User %s already exists.\n' "$name" >&2
		exit 1
	fi

	# Ask before creating the user, so aborting here leaves nothing behind.
	while [[ "$MODE" == "gui" ]]; do
		# the window asks twice and checks they match
		gui_ask "{\"type\":\"password\",\"prompt\":$(json_str "Password for $name")}"
		password="$ANSWER"
		[[ -n "$password" ]] && break
	done
	while [[ "$MODE" != "gui" ]]; do
		read -rs -p "Password for $name: " password
		printf '\n'
		if [[ -z "$password" ]]; then
			printf 'The password cannot be empty.\n' >&2
			continue
		fi
		read -rs -p "Confirm password: " confirm
		printf '\n'
		[[ "$password" == "$confirm" ]] && break
		printf 'Passwords do not match, try again.\n' >&2
	done

	# Authenticate once first: the pipe below runs two sudo at the same time.
	sudo -v
	# In wheel so the user can use sudo.
	sudo useradd -m -G wheel -- "$name"
	CREATED_USER="$name"
	printf '%s:%s\n' "$name" "$password" | sudo chpasswd
	printf 'Password set for %s.\n' "$name"
	unset password confirm

	home="$(getent passwd -- "$name" | cut -d: -f6)"
	sudo cp -a -- "$DOTFILES_DIR" "$home/dotfiles"
	sudo chown -R -- "$name:" "$home/dotfiles"
	printf 'Copied %s to %s/dotfiles\n' "$DOTFILES_DIR" "$home"

	# Scan the hardware now, with our sudo, so the new user never needs it.
	local -a args=(--current-user "--$MODE")
	[[ "$MODE" == "gui" ]] && args=(--current-user --gui-backend)
	if command -v nixos-generate-config >/dev/null 2>&1; then
		sudo nixos-generate-config --show-hardware-config \
			| sudo -u "$name" tee "$home/.hardware-configuration.nix" >/dev/null
		args+=(--hardware-config "$home/.hardware-configuration.nix")
	fi

	sudo -iu "$name" "$home/dotfiles/install.sh" "${args[@]}" || status=$?
	exit "$status"
}

backup_and_link() {
	local source="$1"
	local target="$2"
	local parent backup

	parent="$(dirname -- "$target")"
	mkdir -p "$parent"

	if [[ -e "$target" || -L "$target" ]]; then
		if ask_yes_no "'$target' exists. Create a backup first?" "y"; then
			backup="$target.backup.$(date +%Y%m%d-%H%M%S)"
			mv -- "$target" "$backup"
			printf 'Backed up %s to %s\n' "$target" "$backup"
		else
			rm -rf -- "$target"
		fi
	fi

	ln -s -- "$source" "$target"
	printf 'Linked %s -> %s\n' "$target" "$source"
}

# Modules are all the .nix files under nixos/modules, subfolders included
# (e.g. epita/c.nix), as paths relative to nixos/modules.
# Modules not shown in the module list: they get their own question with a
# warning (see ask_risky_modules).
RISKY_MODULES=("passwordless-rebuild.nix")

# Modules a host can import: top-level ones and the core.nix of each group
# (a group's core.nix imports its own submodules).
list_modules() {
	(
		cd -- "$MODULES_DIR"
		find . -type f -name '*.nix' -printf '%P\n' | while IFS= read -r module; do
			if [[ "$module" == */* && "$module" != */core.nix && -f "${module%/*}/core.nix" ]]; then
				continue
			fi
			printf '%s\n' "$module"
		done
	) | sort | grep -vxF -f <(printf '%s\n' "${RISKY_MODULES[@]}")
}

ask_risky_modules() {
	printf '\n\e[1;33mWarning:\e[0m passwordless-rebuild lets wheel users run '\''sudo nixos-rebuild'\'' without a password.\n' >&2
	printf 'nixos-rebuild can switch to any config as root, so anything running as your user\n' >&2
	printf '(scripts, coding agents...) could get root without asking you.\n' >&2
	if ask_yes_no "Enable passwordless nixos-rebuild?" "n"; then
		MODULE_OPTIONS+=("passwordless-rebuild")
		MODULE_CHECKED+=(1)
	fi
}

# Modules enabled (not commented out) in the default host's imports, used as
# preselection.
default_modules() {
	sed -nE 's#^[[:space:]]*(\./)?(\.\./)+modules/([^[:space:]#]+\.nix).*$#\3#p' \
		"$HOSTS_DIR/default/configuration.nix"
}

# The import lines of the selected modules, one per module, commented out
# when disabled (as nixcfg writes them).
module_imports() {
	local i
	for i in "${!MODULE_OPTIONS[@]}"; do
		if (( MODULE_CHECKED[i] )); then
			printf '    ./../../modules/%s.nix\n' "${MODULE_OPTIONS[$i]}"
		else
			printf '    # ./../../modules/%s.nix\n' "${MODULE_OPTIONS[$i]}"
		fi
	done
}

select_modules() {
	local module i
	local -a defaults
	MODULE_OPTIONS=()
	MODULE_CHECKED=()

	mapfile -t defaults < <(default_modules)
	if (( WANT_LIFE_MANAGER )); then
		# its run.sh uses 'tailscale serve'
		defaults+=("life-manager.nix" "tailscale.nix")
	fi

	while IFS= read -r module; do
		MODULE_OPTIONS+=("${module%.nix}")
		MODULE_CHECKED+=(0)
		for i in "${defaults[@]}"; do
			if [[ "$i" == "$module" ]]; then
				MODULE_CHECKED[-1]=1
				break
			fi
		done
	done < <(list_modules)

	printf '\n'
	select_many "Modules to import:" MODULE_OPTIONS MODULE_CHECKED
}

# Desktops are the files of nixos/modules/desktop (but default.nix, which
# defines the options), enabled per host with desktop.enabled.
list_desktops() {
	find "$MODULES_DIR/desktop" -mindepth 1 -maxdepth 1 -name '*.nix' ! -name default.nix -printf '%f\n' \
		| sed 's/\.nix$//' | sort
}

# Desktops enabled (not commented out) in the default host, used as preselection.
default_desktops() {
	sed -n '/desktop\.enabled = \[/,/\];/p' "$HOSTS_DIR/default/configuration.nix" \
		| sed -nE 's/^[[:space:]]*"([a-z0-9_-]+)".*$/\1/p'
}

select_desktops() {
	local desktop i
	local -a defaults chosen=()
	DESKTOP_OPTIONS=()
	DESKTOP_CHECKED=()
	DEFAULT_SESSION=""

	mapfile -t defaults < <(default_desktops)
	(( WANT_CAELESTIA )) && defaults+=("caelestia")

	while IFS= read -r desktop; do
		DESKTOP_OPTIONS+=("$desktop")
		DESKTOP_CHECKED+=(0)
		for i in "${defaults[@]}"; do
			[[ "$i" == "$desktop" ]] && DESKTOP_CHECKED[-1]=1
		done
	done < <(list_desktops)

	printf '\n'
	select_many "Desktops (all selectable on the login screen):" DESKTOP_OPTIONS DESKTOP_CHECKED

	for i in "${!DESKTOP_OPTIONS[@]}"; do
		(( DESKTOP_CHECKED[i] )) && chosen+=("${DESKTOP_OPTIONS[$i]}")
	done
	(( ${#chosen[@]} )) || return 0

	# Choosing the caelestia desktop also runs 'caelestia install' afterwards.
	for i in "${chosen[@]}"; do
		[[ "$i" == "caelestia" ]] && WANT_CAELESTIA=1
	done

	DEFAULT_SESSION="${chosen[0]}"
	if (( ${#chosen[@]} > 1 )); then
		local current=0
		for i in "${!chosen[@]}"; do
			(( WANT_CAELESTIA )) && [[ "${chosen[$i]}" == "caelestia" ]] && current="$i"
		done
		printf '\n'
		select_one "Desktop preselected on the login screen:" "$current" "${chosen[@]}"
		DEFAULT_SESSION="${chosen[$SELECTED]}"
	fi
}

# The desktop.enabled lines, commented out when disabled (as nixcfg writes them).
desktop_lines() {
	local i
	for i in "${!DESKTOP_OPTIONS[@]}"; do
		if (( DESKTOP_CHECKED[i] )); then
			printf '    "%s"\n' "${DESKTOP_OPTIONS[$i]}"
		else
			printf '    # "%s"\n' "${DESKTOP_OPTIONS[$i]}"
		fi
	done
}

# The NixOS release this machine was installed with: the one in its
# /etc/nixos/configuration.nix, else the running release.
detect_state_version() {
	local version=""
	if [[ -r /etc/nixos/configuration.nix ]]; then
		version="$(sed -nE 's/^[[:space:]]*system\.stateVersion[[:space:]]*=[[:space:]]*"([0-9.]+)".*$/\1/p' \
			/etc/nixos/configuration.nix | head -n1)"
	fi
	if [[ -z "$version" ]] && command -v nixos-version >/dev/null 2>&1; then
		version="$(nixos-version | cut -d. -f1,2)"
	fi
	ask_text "NixOS release this machine was installed with (system.stateVersion)" "$version" '^[0-9]{2}\.[0-9]{2}$'
	if ! [[ "$ANSWER" =~ ^[0-9]{2}\.[0-9]{2}$ ]]; then
		printf 'Expected a release like 25.05, got: %s\n' "$ANSWER" >&2
		exit 1
	fi
	STATE_VERSION="$ANSWER"
}

# The file under nixos/ that installs a tool (e.g. modules/razer.nix), if any.
tool_provider() {
	grep -rlF --include='*.nix' -- "tools/$1 " "$DOTFILES_DIR/nixos" \
		| head -n1 | sed "s#^$DOTFILES_DIR/nixos/##"
}

# Whether the selected modules (or core.nix, always imported) already install it.
tool_installed() {
	local provider="$1" i
	[[ "$provider" == "core.nix" ]] && return 0
	for i in "${!DESKTOP_OPTIONS[@]}"; do
		(( DESKTOP_CHECKED[i] )) && [[ "modules/desktop/${DESKTOP_OPTIONS[$i]}.nix" == "$provider" ]] && return 0
	done
	for i in "${!MODULE_OPTIONS[@]}"; do
		(( MODULE_CHECKED[i] )) && [[ "modules/${MODULE_OPTIONS[$i]}.nix" == "$provider" ]] && return 0
	done
	return 1
}

# Tools from tools/ that the chosen modules don't install already, to add to
# the host's packages. Hyprland plugins (hypr-*) are left out: they are loaded
# by the caelestia desktop, not installed as packages.
select_tools() {
	local tool provider
	local -a included=()
	TOOL_OPTIONS=()
	TOOL_LABELS=()
	TOOL_CHECKED=()

	while IFS= read -r tool; do
		[[ "$tool" == hypr-* ]] && continue
		# the installer itself
		[[ "$tool" == installer-gui ]] && continue
		provider="$(tool_provider "$tool")"
		if [[ -n "$provider" ]] && tool_installed "$provider"; then
			included+=("$tool")
			continue
		fi
		TOOL_OPTIONS+=("$tool")
		if [[ -n "$provider" ]]; then
			TOOL_LABELS+=("$tool (normally from ${provider#modules/})")
		else
			TOOL_LABELS+=("$tool")
		fi
		TOOL_CHECKED+=(0)
	done < <(find "$DOTFILES_DIR/tools" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

	printf '\n'
	(( ${#included[@]} )) && printf 'Tools already installed by your modules: %s\n' "${included[*]}"
	select_many "Extra tools to install:" TOOL_LABELS TOOL_CHECKED
}

# The package lines of the selected tools, for environment.systemPackages.
tool_packages() {
	local i tool
	for i in "${!TOOL_OPTIONS[@]}"; do
		(( TOOL_CHECKED[i] )) || continue
		tool="${TOOL_OPTIONS[$i]}"
		printf '    # tools/%s\n' "$tool"
		case "$tool" in
			bat-swarm)
				printf '    (import ./../../../tools/bat-swarm {\n'
				printf '      inherit pkgs;\n'
				printf '      quickshell = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;\n'
				printf '    })\n'
				;;
			*) printf '    (import ./../../../tools/%s { inherit pkgs; })\n' "$tool" ;;
		esac
	done
}

write_host_config() {
	local config_file="$1"
	local hostname="$2"
	local username="$3"
	local session_line=""

	[[ -n "$DEFAULT_SESSION" ]] && session_line="  desktop.defaultSession = \"$DEFAULT_SESSION\";"

	cat > "$config_file" <<EOF
{ config, pkgs, lib, inputs, ... }:

{
  networking.hostName = "$hostname";

  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix

    # You probably shouldn't remove it
    ./../../core.nix

    # Modules: comment a line out to disable it (or use \`nixcfg\`)
$(module_imports)
  ];

  # Desktops: all selectable on the login screen (or use \`nixcfg\`).
  # caelestia also turns hyprland on. See nixos/modules/desktop/default.nix
  desktop.enabled = [
$(desktop_lines)
  ];
$session_line

  # Packages for this host only
  environment.systemPackages = with pkgs; [
$(tool_packages)
  ];

  users.users."$username" = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" "docker" ];
  };

  # NixOS release this host was installed with: keep it, even after upgrades
  # (read \`man configuration.nix\` before changing it).
  system.stateVersion = "$STATE_VERSION";
}
EOF
}

setup_nixos() {
	local hostname username host_dir config_file hardware_file

	printf '\n'
	if ! ask_yes_no "Create a new NixOS host configuration?" "y"; then
		return
	fi

	ask_text "Hostname" "" '^[a-zA-Z0-9_-]+$'
	hostname="$ANSWER"
	# The target user was already chosen at the start (we run as that user).
	username="$USER"

	if ! valid_name "$hostname"; then
		printf 'Hostname may contain only letters, numbers, underscores, and hyphens.\n' >&2
		exit 1
	fi

	host_dir="$HOSTS_DIR/$hostname"
	if [[ -e "$host_dir" ]]; then
		printf 'Host directory already exists: %s\n' "$host_dir" >&2
		exit 1
	fi

	if [[ -n "$HARDWARE_CONFIG" && ! -f "$HARDWARE_CONFIG" ]]; then
		printf 'Hardware config not found: %s\n' "$HARDWARE_CONFIG" >&2
		exit 1
	fi
	if [[ -z "$HARDWARE_CONFIG" ]] && ! command -v nixos-generate-config >/dev/null 2>&1; then
		printf 'nixos-generate-config was not found; run this script on NixOS.\n' >&2
		exit 1
	fi

	select_desktops
	select_modules
	ask_risky_modules
	select_tools
	detect_state_version

	mkdir -p "$host_dir"
	config_file="$host_dir/configuration.nix"
	hardware_file="$host_dir/hardware-configuration.nix"

	write_host_config "$config_file" "$hostname" "$username"
	printf 'Wrote %s\n' "$config_file"

	if [[ -n "$HARDWARE_CONFIG" ]]; then
		cp -- "$HARDWARE_CONFIG" "$hardware_file"
	else
		sudo nixos-generate-config --show-hardware-config > "$hardware_file"
	fi

	# flake.nix builds one configuration per directory in nixos/hosts/, but a
	# flake only sees files tracked by git: add the new host so it is picked up.
	if git -C "$DOTFILES_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		git -C "$DOTFILES_DIR" add -- "$host_dir"
		printf 'Added %s to git (flake.nix picks up every host in nixos/hosts/).\n' "$host_dir"
	else
		printf 'Warning: %s is not a git repository; the flake may not see the new host.\n' "$DOTFILES_DIR" >&2
	fi

	printf 'Apply it with: sudo nixos-rebuild switch --flake %s#%s\n' "$DOTFILES_DIR" "$hostname"
}

# Projects that live in their own (private) repos, cloned where the dotfiles
# expect them: "name|repo|path relative to \$HOME".
PROJECTS=(
	"nova|Dralexgon/nova|dev/ai/nova"
	"life-manager|Dralexgon/life-manager|dev/apps/life-manager"
)

clone_projects() {
	local i name repo path
	local -a project_labels=() project_checked=() todo=()

	for i in "${PROJECTS[@]}"; do
		IFS='|' read -r name repo path <<<"$i"
		if [[ -e "$HOME/$path" ]]; then
			printf '%s is already at ~/%s.\n' "$name" "$path"
			[[ "$name" == "life-manager" ]] && WANT_LIFE_MANAGER=1
			continue
		fi
		todo+=("$i")
		project_labels+=("$name -> ~/$path")
		project_checked+=(0)
	done
	(( ${#todo[@]} )) || return 0

	printf '\n'
	select_many "Projects to clone (separate repos):" project_labels project_checked

	for i in "${!todo[@]}"; do
		(( project_checked[i] )) || continue
		IFS='|' read -r name repo path <<<"${todo[$i]}"
		mkdir -p -- "$(dirname -- "$HOME/$path")"
		printf 'Cloning %s into ~/%s\n' "$repo" "$path"
		# The repos are private: gh uses its login, git asks for credentials.
		if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
			gh repo clone "$repo" "$HOME/$path" || true
		else
			git clone "https://github.com/$repo.git" "$HOME/$path" || true
		fi
		if [[ -d "$HOME/$path/.git" ]]; then
			[[ "$name" == "life-manager" ]] && WANT_LIFE_MANAGER=1
		else
			printf 'Could not clone %s. Retry later with: gh repo clone %s ~/%s\n' "$repo" "$repo" "$path" >&2
		fi
	done
	return 0
}

install_caelestia() {
	local name state i
	local -a enabled=() disabled=()
	CAELESTIA_OPTIONS=()
	CAELESTIA_CHECKED=()

	(( WANT_CAELESTIA )) || return 0

	if ! command -v caelestia >/dev/null 2>&1; then
		printf '\nThe caelestia CLI is not installed yet. It comes with the caelestia module:\n'
		printf 'rebuild NixOS, then run '\''caelestia install'\'' (or this script again).\n'
		return
	fi

	# Parse "name  (default|off)" lines from the CLI's component list.
	while read -r name state; do
		CAELESTIA_OPTIONS+=("$name")
		if [[ "$state" == "(default)" ]]; then
			CAELESTIA_CHECKED+=(1)
		else
			CAELESTIA_CHECKED+=(0)
		fi
	done < <(caelestia install --help 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
		| sed -nE 's/^[[:space:]]+([a-z0-9_-]+)[[:space:]]+(\((default|off)\))$/\1 \2/p')

	if (( ${#CAELESTIA_OPTIONS[@]} == 0 )); then
		if [[ "$MODE" == "gui" ]]; then
			caelestia install --noconfirm </dev/null
		else
			caelestia install
		fi
		return
	fi

	printf '\n'
	select_many "Caelestia components:" CAELESTIA_OPTIONS CAELESTIA_CHECKED
	for i in "${!CAELESTIA_OPTIONS[@]}"; do
		if (( CAELESTIA_CHECKED[i] )); then
			enabled+=("${CAELESTIA_OPTIONS[$i]}")
		else
			disabled+=("${CAELESTIA_OPTIONS[$i]}")
		fi
	done

	local -a args=()
	(( ${#enabled[@]} )) && args+=(--enable-components "$(IFS=,; printf '%s' "${enabled[*]}")")
	(( ${#disabled[@]} )) && args+=(--disable-components "$(IFS=,; printf '%s' "${disabled[*]}")")
	if [[ "$MODE" == "gui" ]]; then
		# No terminal for its prompts (and its stdin is the window's answers):
		# take the defaults, the components were picked above
		caelestia install --noconfirm "${args[@]}" </dev/null
	else
		caelestia install "${args[@]}"
	fi
}

configure_dotfiles() {
	local i source target config_name
	DOTFILE_OPTIONS=("bash")
	DOTFILE_CHECKED=(0)

	while IFS= read -r config_name; do
		[[ "$config_name" == "bash" ]] && continue
		# config/zen is not linked: it's the Zen sidebar layout, restored with `zen-sidebar apply`
		[[ "$config_name" == "zen" ]] && continue
		DOTFILE_OPTIONS+=("$config_name")
		if (( WANT_CAELESTIA )) && [[ "$config_name" == "caelestia" ]]; then
			DOTFILE_CHECKED+=(1)
		else
			DOTFILE_CHECKED+=(0)
		fi
	done < <(find "$DOTFILES_DIR/config" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

	printf '\n'
	select_many "Config groups to link:" DOTFILE_OPTIONS DOTFILE_CHECKED

	local link
	for i in "${!DOTFILE_OPTIONS[@]}"; do
		(( DOTFILE_CHECKED[i] )) || continue
		dotfile_links "${DOTFILE_OPTIONS[$i]}"
		for link in "${DOTFILE_LINKS[@]}"; do
			source="${link%%|*}"
			target="${link#*|}"
			# absolute sources (from the private repo) are used as they are
			[[ "$source" == /* ]] || source="$DOTFILES_DIR/config/$source"
			backup_and_link "$source" "$target"
		done
	done
	[[ -d "$HOME/.ssh" ]] && chmod 700 "$HOME/.ssh"
	return 0
}

# Fills DOTFILE_LINKS with "source|target" pairs for a config group: source is
# relative to config/, or absolute for files from $PRIVATE_DIR. Groups not listed here link to ~/.config/<group>.
dotfile_links() {
	case "$1" in
		bash) DOTFILE_LINKS=("bash/bashrc|$HOME/.bashrc") ;;
		git)
			DOTFILE_LINKS=(
				"git/gitconfig|$HOME/.gitconfig"
				"git/gitconfig-public|$HOME/.gitconfig-public"
			)
			# work identity only when the private repo is cloned
			[[ -f "$PRIVATE_DIR/git/gitconfig-work" ]] &&
				DOTFILE_LINKS+=("$PRIVATE_DIR/git/gitconfig-work|$HOME/.gitconfig-work")
			;;
		ssh) DOTFILE_LINKS=("ssh/config|$HOME/.ssh/config") ;; # never the keys
		clang-format) DOTFILE_LINKS=("clang-format/clang-format|$HOME/.clang-format") ;;
		*) DOTFILE_LINKS=("$1|$HOME/.config/$1") ;;
	esac
}

while (( $# > 0 )); do
	case "$1" in
		-t|--tui)
			MODE="tui"
			;;
		-i|--input)
			MODE="input"
			;;
		-g|--gui)
			MODE="gui-launch"
			;;
		--gui-backend)
			# run by tools/installer-gui, not by hand
			MODE="gui"
			;;
		--current-user)
			ASK_USER=0
			;;
		--hardware-config)
			if (( $# < 2 )); then
				printf 'Missing file for --hardware-config\n\n' >&2
				usage >&2
				exit 1
			fi
			HARDWARE_CONFIG="$2"
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			printf 'Unknown option: %s\n\n' "$1" >&2
			usage >&2
			exit 1
			;;
	esac
	shift
done

if [[ "$MODE" == "gui-launch" ]]; then
	gui_args=("$DOTFILES_DIR")
	(( ASK_USER )) || gui_args+=(--current-user)
	[[ -n "$HARDWARE_CONFIG" ]] && gui_args+=(--hardware-config "$HARDWARE_CONFIG")
	if command -v installer-gui >/dev/null 2>&1; then
		exec installer-gui "${gui_args[@]}"
	fi
	printf 'Starting the installer window through nix run (the first time downloads GTK)...\n'
	exec nix --extra-experimental-features 'nix-command flakes' run "$DOTFILES_DIR#installer-gui" -- "${gui_args[@]}"
fi

if [[ "$MODE" == "tui" ]] && ! [[ -t 0 && -t 2 ]]; then
	MODE="input"
fi

if [[ "$MODE" == "gui" ]]; then
	# No terminal: sudo asks through a window (SUDO_ASKPASS, set by installer-gui),
	# and git must not wait for a password on a terminal nobody sees.
	sudo() { command sudo -A "$@"; }
	export GIT_TERMINAL_PROMPT=0
fi
trap on_exit EXIT

if (( ASK_USER )); then
	choose_user
fi

if ask_yes_no "Install Caelestia (Hyprland shell and dots)?" "n"; then
	WANT_CAELESTIA=1
fi

clone_projects
setup_nixos
install_caelestia
configure_dotfiles
printf '\nInstallation complete.\n'
