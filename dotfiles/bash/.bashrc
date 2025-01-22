# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
[[ $- == *i* ]] || return
[[ $(tty) != /dev/tty* ]] || return

# Setup your variables
EDITOR='nvim'
CONFIGURATION_NIX_FILE='/etc/nixos/configuration.nix'

# Bash prompt
PINK='\033[01;95m'
WHITE='\033[01;00m'
PS1="\
\[$PINK\][\u@\h@\w]
\[$PINK\]uwu~ \[$WHITE\]"

# Nix shortcuts
alias alex-nix-conf="$EDITOR $CONFIGURATION_NIX_FILE"
alias alex-nix-rebuild-switch="sudo nixos-rebuild switch"
alias alex-nix-rebuild-reboot="sudo nixos-rebuild switch && reboot"
alias alex-nix-generation-list="nixos-rebuild list-generations"
alex-nix-clean-generation() { # Usage examples: nix-clean-generation 1 2 3
    sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations "$@"
    nix-collect-garbage
}
alias alex-nix-package-list="nix-store -q --requisites /run/current-system | awk -F'-' '/\/nix\/store/ {print \$(NF-1)}' | sort -u"

alias alex-sh-conf="$EDITOR ~/.bashrc"
alias alex-sh-update="source ~/.bashrc"

alias alex-hyprland="$EDITOR .config/hypr/hyprland.conf"

acp() {
    git add .
    git commit -m "$1"
    git push
}

acpmt() {
    git add .
    git commit -m "$1"
    git tag -a "$1" -m "$1"
    git push --follow-tags
}

swapf() {
    if [ "$#" -ne 2 ]; then
        echo "Usage: swapf file1 file2"
        return 1
    fi

    file1="$1"
    file2="$2"
    tempfile=$(mktemp)

    if [ ! -e "$file1" ] || [ ! -e "$file2" ]; then
        echo "Error: Both files must exist."
        return 1
    fi

    mv "$file1" "$tempfile" && mv "$file2" "$file1" && mv "$tempfile" "$file2"

    if [ $? -eq 0 ]; then
        echo "Swapped: $file1 <--> $file2"
    else
        echo "Error: File swapping failed."
    fi
}

#You can add your own custom commands here
if [ -f ~/.bashrc-personal ]; then
    source ~/.bashrc-personal
fi

fastfetch
