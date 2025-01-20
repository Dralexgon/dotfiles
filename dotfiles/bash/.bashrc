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
alias alexnix-conf="$EDITOR $CONFIGURATION_NIX_FILE"
alias alexnix-rebuild-switch="sudo nixos-rebuild switch && reboot"
alias alexnix-rebuild-reboot="sudo nixos-rebuild switch && reboot"
alias alexnix-generation-list="nixos-rebuild list-generations"
alexnix-clean-generation() { # Usage examples: nix-clean-generation 1 2 3
    sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations "$@"
    nix-collect-garbage
}
alias alexnix-package-list="nix-store -q --requisites /run/current-system | awk -F'-' '/\/nix\/store/ {print \$(NF-1)}' | sort -u"

alias alexrc-conf="$EDITOR ~/.bashrc"
alias alexrc-update="source ~/.bashrc"

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
