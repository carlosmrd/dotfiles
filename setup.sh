#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 &&
    pwd
)"

# Initial validation

[[ -n "${HOME:-}" && -d "$HOME" ]] ||
    {
        echo "setup.sh: invalid HOME." >&2
        exit 1
    }

BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

# System packages (mirrors README; idempotent via --needed)

PACMAN_PKGS=(
    adw-gtk-theme
    btop
    fastfetch
    fish
    fisher
    git
    jq
    kitty
    lib32-mangohud
    libreoffice-fresh
    mangohud
    mpv
    nautilus
    niri
    noctalia
    noctalia-greeter
    noto-fonts
    openrgb
    opentabletdriver
    papirus-icon-theme
    pavucontrol
    pipewire
    pipewire-alsa
    pipewire-jack
    pipewire-pulse
    stow
    sunshine
    ttf-ibm-plex
    ttf-jetbrains-mono-nerd
    wireplumber
    xdg-desktop-portal
    xdg-desktop-portal-gtk
    zed
    zen-browser-bin
    zip
)

if command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --needed "${PACMAN_PKGS[@]}"
else
    echo "setup.sh: pacman missing; skipping system packages." >&2
fi

if command -v paru >/dev/null 2>&1; then
    paru -S --needed bibata-cursor-theme-bin
else
    echo "setup.sh: paru missing; skipping bibata-cursor-theme-bin." >&2
fi

command -v stow >/dev/null 2>&1 ||
    {
        echo "setup.sh: stow is not installed." >&2
        exit 1
    }

[[ -d "$DOTFILES/images/Icons" ]] ||
    {
        echo "setup.sh: images/Icons missing." >&2
        exit 1
    }

[[ -d "$DOTFILES/images/Wallpapers" ]] ||
    {
        echo "setup.sh: images/Wallpapers missing." >&2
        exit 1
    }

[[ -f "$DOTFILES/images/Icons/Eblana.jpg" ]] ||
    {
        echo "setup.sh: images/Icons/Eblana.jpg missing." >&2
        exit 1
    }

# Stow packages

PACKAGES=(
    btop
    fastfetch
    fish
    gtk
    kitty
    mangohud
    mpv
    niri
    noctalia
    openrgb
    opentabletdriver
    pipewire
    sunshine
    wireplumber
    xdg
    zed
    zen
)

for package in "${PACKAGES[@]}"; do
    [[ -d "$DOTFILES/$package" ]] ||
        {
            echo "setup.sh: missing Stow package: $package" >&2
            exit 1
        }
done

TARGETS=(
    .config/btop
    .config/fastfetch
    .config/fish
    .config/gtk-3.0
    .config/gtk-4.0
    .config/kitty
    .config/MangoHud
    .config/mpv
    .config/niri
    .config/noctalia
    .config/OpenRGB
    .config/OpenTabletDriver
    .config/pipewire
    .config/sunshine
    .config/wireplumber
    .config/xdg-desktop-portal
    .config/zed
    ".config/zen/profiles.ini"
    ".config/zen/installs.ini"
    ".config/zen/3yi7xldz.Default (release)/user.js"
    ".config/zen/3yi7xldz.Default (release)/zen-themes.json"
    ".config/zen/3yi7xldz.Default (release)/containers.json"
    ".config/zen/3yi7xldz.Default (release)/chrome/userChrome.css"
    ".config/zen/3yi7xldz.Default (release)/chrome/userContent.css"
)

# Remove old configs (all validation happens before this point)

if ! STOW_CHECK="$(stow -n -R -d "$DOTFILES" -t "$HOME" "${PACKAGES[@]}" 2>&1)"; then
    UNRESOLVED=0
    SEEN_CONFLICT=0

    while IFS= read -r line; do
        case "$line" in
            *"existing target "*)
                SEEN_CONFLICT=1
                rest="${line##*existing target }"
                conflict="${rest% since *}"

                covered=0

                for t in "${TARGETS[@]}"; do
                    if [[ "$conflict" == "$t" || "$conflict" == "$t/"* ]]; then
                        covered=1
                        break
                    fi
                done

                if [[ "$covered" -eq 0 ]]; then
                    echo "setup.sh: conflict outside managed dirs: $conflict" >&2
                    UNRESOLVED=1
                fi
                ;;
        esac
    done <<< "$STOW_CHECK"

    if [[ "$SEEN_CONFLICT" -eq 0 ]]; then
        echo "$STOW_CHECK" >&2
        UNRESOLVED=1
    fi

    if [[ "$UNRESOLVED" -ne 0 ]]; then
        echo "setup.sh: Stow simulation failed; nothing was removed." >&2
        exit 1
    fi

    echo "setup.sh: conflicts under managed dirs will be resolved by recreation."
fi

# Back up managed dirs (everything removed below)

mkdir -p "$BACKUP"

for target in "${TARGETS[@]}"; do
    src="$HOME/$target"
    [[ -e "$src" || -L "$src" ]] || continue

    if [[ -L "$src" ]] && [[ "$(readlink -f "$src")" == "$DOTFILES/"* ]]; then
        continue
    fi

    mkdir -p "$BACKUP/$(dirname "$target")"

    cp -a "$src" "$BACKUP/$target"
done

if find "$BACKUP" -mindepth 1 -print -quit | grep -q .; then
    echo "backup: $BACKUP"
else
    rmdir "$BACKUP"
fi

for target in "${TARGETS[@]}"; do
    rm -rf "$HOME/$target"
done

# Icons and wallpapers (copied, not stow-managed)

shopt -s nullglob

mkdir -p "$HOME/Pictures/Icons" "$HOME/Pictures/Wallpapers"

for src in "$DOTFILES"/images/Icons/*; do
    [[ -f "$src" ]] || continue
    install -Dm644 "$src" "$HOME/Pictures/Icons/$(basename "$src")"
done

for src in "$DOTFILES"/images/Wallpapers/*; do
    [[ -f "$src" ]] || continue
    install -Dm644 "$src" "$HOME/Pictures/Wallpapers/$(basename "$src")"
done

shopt -u nullglob

# Restow packages

stow \
    -R \
    -d "$DOTFILES" \
    -t "$HOME" \
    "${PACKAGES[@]}"

# User services

if command -v systemctl >/dev/null 2>&1; then

    systemctl --user stop \
        xdg-desktop-portal.service \
        2>/dev/null || true

    systemctl --user start \
        xdg-desktop-portal.service \
        2>/dev/null || true

    for unit in \
        pipewire.service \
        pipewire-pulse.service \
        wireplumber.service
    do
        systemctl --user restart "$unit" \
            2>/dev/null || true
    done

    systemctl --user restart \
        opentabletdriver.service \
        2>/dev/null || true
fi

# Noctalia

if command -v noctalia >/dev/null 2>&1; then
    noctalia msg config-reload \
        2>/dev/null || true
    # Regenerate template outputs (untracked; apps include them)
    noctalia msg templates-apply \
        2>/dev/null || true
fi

# Fisher plugins (after stow: needs linked fish config)

if fish -c 'functions -q fisher' 2>/dev/null; then
    fish -c 'fisher install pure-fish/pure jorgebucaran/autopair.fish franciscolourenco/done'
else
    echo "setup.sh: fisher missing; skipping fish plugins." >&2
fi

# GTK settings

if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface font-name 'IBM Plex Sans 11' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Ice' 2>/dev/null || true
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
else
    echo "setup.sh: gsettings missing; skipping GTK settings." >&2
fi

# Default shell

if command -v fish >/dev/null 2>&1 && command -v chsh >/dev/null 2>&1; then
    if [[ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v fish)" ]]; then
        chsh -s "$(command -v fish)" || echo "setup.sh: chsh failed; set your shell manually." >&2
    fi
else
    echo "setup.sh: fish or chsh missing; skipping default shell." >&2
fi

echo
echo "done - log out and back in for the default shell; new terminals pick up the configs"
