#!/usr/bin/env bash

set -euo pipefail

DOTFILES_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HOSTS_DIR="$DOTFILES_DIR/nixos/hosts"
FLAKE_FILE="$DOTFILES_DIR/flake.nix"

read_answer() {
	local prompt="$1"
	local default_answer="$2"
	local answer

	read -r -p "$prompt" answer
	printf '%s' "${answer:-$default_answer}"
}

valid_name() {
	[[ "$1" =~ ^[a-zA-Z0-9_-]+$ ]]
}

backup_and_link() {
	local source="$1"
	local target="$2"
	local parent backup answer

	parent="$(dirname -- "$target")"
	mkdir -p "$parent"

	if [[ -e "$target" || -L "$target" ]]; then
		answer="$(read_answer "'$target' exists. Create a backup first? [Y/n] " "y")"
		if [[ "$answer" =~ ^[Yy]$ ]]; then
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

setup_nixos() {
	local hostname username host_dir config_file hardware_file answer temp_file

	answer="$(read_answer "Skip NixOS host setup and go straight to dotfile configuration? [y/N] " "n")"
	if [[ "$answer" =~ ^[Yy]$ ]]; then
		return
	fi

	read -r -p "Hostname: " hostname
	read -r -p "Username [$USER]: " username
	username="${username:-$USER}"

	if ! valid_name "$hostname" || ! valid_name "$username"; then
		printf 'Hostname and username may contain only letters, numbers, underscores, and hyphens.\n' >&2
		exit 1
	fi

	host_dir="$HOSTS_DIR/$hostname"
	if [[ -e "$host_dir" ]]; then
		printf 'Host directory already exists: %s\n' "$host_dir" >&2
		exit 1
	fi

	mkdir -p "$host_dir"
	config_file="$host_dir/configuration.nix"
	hardware_file="$host_dir/hardware-configuration.nix"

	sed \
		-e "s/networking.hostName = \"nixos\";/networking.hostName = \"$hostname\";/" \
		-e 's#^    /etc/nixos/hardware-configuration.nix#    ./hardware-configuration.nix#' \
		"$HOSTS_DIR/default/configuration.nix" > "$config_file"

		sed -i '$d' "$config_file"
		cat >> "$config_file" <<EOF

  users.users."$username" = {
	isNormalUser = true;
	extraGroups = [ "networkmanager" "wheel" "docker" ];
  };
}
EOF

	if ! command -v nixos-generate-config >/dev/null 2>&1; then
		printf 'nixos-generate-config was not found; remove %s and run this script again on NixOS.\n' "$host_dir" >&2
		exit 1
	fi
	sudo nixos-generate-config --show-hardware-config > "$hardware_file"

	if rg -q "nixosConfigurations\.\"$hostname\"" "$FLAKE_FILE"; then
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
}

configure_dotfiles() {
	local choice selected source target config_name
	local -a options=("bash|$HOME/.bashrc")

	while IFS= read -r config_name; do
		[[ "$config_name" == "bash" ]] && continue
		options+=("$config_name|$HOME/.config/$config_name")
	done < <(find "$DOTFILES_DIR/config" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)

	printf '\nAvailable config groups:\n'
	for choice in "${!options[@]}"; do
		printf '  %d) %s\n' "$((choice + 1))" "${options[$choice]%%|*}"
	done
	printf 'Enter numbers separated by spaces (or press Enter to skip): '
	read -r selected

	for choice in $selected; do
		if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#options[@]} )); then
			printf 'Ignoring invalid selection: %s\n' "$choice" >&2
			continue
		fi
		source="${options[$((choice - 1))]%%|*}"
		target="${options[$((choice - 1))]#*|}"
		if [[ "$source" == "bash" ]]; then
			source="bash/bashrc"
		fi
		backup_and_link "$DOTFILES_DIR/config/$source" "$target"
	done
}

setup_nixos
configure_dotfiles
printf '\nInstallation complete.\n'
