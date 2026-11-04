#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_DIR="$DOTFILES_DIR/nixos/hosts"
MODULES_DIR="$DOTFILES_DIR/nixos/modules"
FLAKE_FILE="$DOTFILES_DIR/flake.nix"

MODE="tui"
WANT_CAELESTIA=0
ASK_USER=1
CREATED_USER=""
HARDWARE_CONFIG=""

usage() {
	cat <<EOF
Usage: $(basename -- "$0") [-t|--tui] [-i|--input] [--current-user] [--hardware-config FILE] [-h|--help]

Interactive installer for these dotfiles.

Steps:
  0. Target user: install for the current user, or create a new user (for
     example to try these dotfiles safely). A new user gets a copy of this
     repo in its home, the installer re-runs as that user, and the command
     to delete it is printed at the end.
  1. Caelestia (optional): asks whether to install Caelestia. If yes, the
     caelestia and hyprland modules are preselected for a new host, and
     'caelestia install' is run with the components you pick.
  2. NixOS host setup (optional): creates nixos/hosts/<hostname>/ with the
     hostname and modules you choose (and the target user), generates
     hardware-configuration.nix, and registers the host in flake.nix.
  3. Dotfile configuration: symlinks selected config groups from config/
     into \$HOME (bash -> ~/.bashrc, others -> ~/.config/<name>), offering
     to back up existing files first.

Options:
  -t, --tui     Pick choices with the arrow keys (default).
  -i, --input   Answer by typing (y/n, numbers). Used automatically when
                not running in a terminal.
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
# Prompts. Every prompt works in both modes; results are returned in globals
# (ANSWER, SELECTED) so the TUI can draw on the terminal without a subshell.
# ---------------------------------------------------------------------------

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

# ask_text PROMPT [DEFAULT] -> ANSWER
ask_text() {
	local prompt="$1"
	local default_answer="${2:-}"
	local suffix=""

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

	ask_text "New username" "dotfiles-test"
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
	while true; do
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

list_modules() {
	(
		cd -- "$MODULES_DIR"
		find . -type f -name '*.nix' -printf '%P\n'
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

# Modules enabled in the default host's state.json, used as preselection.
# (state.json lists one module per line, so no JSON parser is needed.)
default_modules() {
	sed -n '/"modules"/,/\]/p' "$HOSTS_DIR/default/state.json" \
		| sed -nE 's#^[[:space:]]*"([^"]+)",?$#\1.nix#p'
}

select_modules() {
	local module i
	local -a defaults
	MODULE_OPTIONS=()
	MODULE_CHECKED=()

	mapfile -t defaults < <(default_modules)
	if (( WANT_CAELESTIA )); then
		defaults+=("caelestia.nix" "hyprland.nix")
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

write_host_config() {
	local config_file="$1"
	local hostname="$2"
	local username="$3"
	local state_file i
	local -a enabled=()
	state_file="$(dirname -- "$config_file")/state.json"

	cat > "$config_file" <<EOF
{ config, pkgs, lib, inputs, ... }:

{
  networking.hostName = "$hostname";

  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix

    # You probably shouldn't remove it
    ./../../core.nix

    # Enabled modules and extra packages (edit with \`nix run ~/dotfiles#nixcfg\`)
    (import ./../../state.nix ./state.json)
  ];

  users.users."$username" = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" "docker" ];
  };
}
EOF

	# One module per line, as nixcfg writes it.
	for i in "${!MODULE_OPTIONS[@]}"; do
		if (( MODULE_CHECKED[i] )); then
			enabled+=("${MODULE_OPTIONS[$i]}")
		fi
	done
	{
		if (( ${#enabled[@]} )); then
			printf '{\n  "modules": [\n'
			printf '    "%s"\n' "${enabled[@]}" | sed '$!s/$/,/'
			printf '  ],\n'
		else
			printf '{\n  "modules": [],\n'
		fi
		printf '  "packages": []\n}\n'
	} > "$state_file"
}

setup_nixos() {
	local hostname username host_dir config_file hardware_file temp_file

	printf '\n'
	if ! ask_yes_no "Create a new NixOS host configuration?" "y"; then
		return
	fi

	ask_text "Hostname"
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

	select_modules
	ask_risky_modules

	mkdir -p "$host_dir"
	config_file="$host_dir/configuration.nix"
	hardware_file="$host_dir/hardware-configuration.nix"

	write_host_config "$config_file" "$hostname" "$username"
	printf 'Wrote %s and state.json\n' "$config_file"

	if [[ -n "$HARDWARE_CONFIG" ]]; then
		cp -- "$HARDWARE_CONFIG" "$hardware_file"
	else
		sudo nixos-generate-config --show-hardware-config > "$hardware_file"
	fi

	if grep -q "nixosConfigurations\.\"$hostname\"" "$FLAKE_FILE"; then
		printf 'A flake configuration for %s already exists; leaving flake.nix unchanged.\n' "$hostname"
	else
		temp_file="$(mktemp)"
		awk -v hostname="$hostname" -v host_dir="./nixos/hosts/$hostname/configuration.nix" '
			/    packages\.\$\{system\}\.default = \(/ {
				printf "    nixosConfigurations.\"%s\" = nixpkgs.lib.nixosSystem {\n", hostname
				print "      specialArgs = {inherit inputs;};"
				print "      modules = ["
				printf "        %s\n", host_dir
				print "      ];"
				print "    };"
				print ""
			}
			{ print }
		' "$FLAKE_FILE" > "$temp_file"
		mv -- "$temp_file" "$FLAKE_FILE"
		printf 'Registered %s in flake.nix.\n' "$hostname"
	fi

	printf 'Apply it with: sudo nixos-rebuild switch --flake %s#%s\n' "$DOTFILES_DIR" "$hostname"
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
		caelestia install
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
	caelestia install "${args[@]}"
}

configure_dotfiles() {
	local i source target config_name
	DOTFILE_OPTIONS=("bash")
	DOTFILE_CHECKED=(0)

	while IFS= read -r config_name; do
		[[ "$config_name" == "bash" ]] && continue
		DOTFILE_OPTIONS+=("$config_name")
		if (( WANT_CAELESTIA )) && [[ "$config_name" == "caelestia" ]]; then
			DOTFILE_CHECKED+=(1)
		else
			DOTFILE_CHECKED+=(0)
		fi
	done < <(find "$DOTFILES_DIR/config" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

	printf '\n'
	select_many "Config groups to link:" DOTFILE_OPTIONS DOTFILE_CHECKED

	for i in "${!DOTFILE_OPTIONS[@]}"; do
		(( DOTFILE_CHECKED[i] )) || continue
		source="${DOTFILE_OPTIONS[$i]}"
		if [[ "$source" == "bash" ]]; then
			source="bash/bashrc"
			target="$HOME/.bashrc"
		else
			target="$HOME/.config/$source"
		fi
		backup_and_link "$DOTFILES_DIR/config/$source" "$target"
	done
}

while (( $# > 0 )); do
	case "$1" in
		-t|--tui)
			MODE="tui"
			;;
		-i|--input)
			MODE="input"
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

if [[ "$MODE" == "tui" ]] && ! [[ -t 0 && -t 2 ]]; then
	MODE="input"
fi
trap on_exit EXIT

if (( ASK_USER )); then
	choose_user
fi

if ask_yes_no "Install Caelestia (Hyprland shell and dots)?" "n"; then
	WANT_CAELESTIA=1
fi

setup_nixos
install_caelestia
configure_dotfiles
printf '\nInstallation complete.\n'
