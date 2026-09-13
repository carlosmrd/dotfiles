#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 &&
    pwd
)"

# ---------------------------------------------------------------------------
# Validação inicial
# ---------------------------------------------------------------------------

[[ -n "${HOME:-}" && -d "$HOME" ]] ||
    {
        echo "setup.sh: HOME inválido." >&2
        exit 1
    }

BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

command -v stow >/dev/null 2>&1 ||
    {
        echo "setup.sh: stow não está instalado." >&2
        exit 1
    }

[[ -f "$DOTFILES/images/Remielle.png" ]] ||
    {
        echo "setup.sh: images/Remielle.png ausente." >&2
        exit 1
    }

[[ -f "$DOTFILES/images/Eblana.jpg" ]] ||
    {
        echo "setup.sh: images/Eblana.jpg ausente." >&2
        exit 1
    }

[[ -f "$DOTFILES/xdg/.config/xdg-desktop-portal-termfilechooser/yazi-wrapper.sh" ]] ||
    {
        echo "setup.sh: yazi-wrapper.sh ausente no repositório." >&2
        exit 1
    }

# ---------------------------------------------------------------------------
# Pacotes Stow
# ---------------------------------------------------------------------------

PACKAGES=(
    btop
    fastfetch
    fish
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
    yazi
    zed
)

for package in "${PACKAGES[@]}"; do
    [[ -d "$DOTFILES/$package" ]] ||
        {
            echo "setup.sh: pacote Stow ausente: $package" >&2
            exit 1
        }
done

TARGETS=(
    .config/btop
    .config/fastfetch
    .config/fish
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
    .config/xdg-desktop-portal-termfilechooser
    .config/yazi
    .config/zed
)

# ---------------------------------------------------------------------------
# Arquivos que precisam sobreviver à recriação das configs
# ---------------------------------------------------------------------------

shopt -s nullglob

KEEP=(
    "$HOME/.config/fish/fish_variables"

    "$HOME/.config/OpenTabletDriver/Settings.json"

    "$HOME/.config/sunshine/sunshine_state.json"
    "$HOME/.config/sunshine/sunshine.log"
    "$HOME/.config/sunshine/credentials"

    $HOME/.config/niri/config.kdl.backup.*

    "$HOME/.config/OpenRGB/logs"
    "$HOME/.config/OpenTabletDriver/Logs"
    "$HOME/.config/OpenTabletDriver/Plugins"
    "$HOME/.config/OpenRGB/plugins"
)

shopt -u nullglob

# ---------------------------------------------------------------------------
# Backup
# ---------------------------------------------------------------------------

mkdir -p "$BACKUP"

for src in "${KEEP[@]}"; do
    [[ -e "$src" || -L "$src" ]] || continue

    rel="${src#$HOME/}"

    mkdir -p "$BACKUP/$(dirname "$rel")"

    cp -a "$src" "$BACKUP/$rel"
done

if find "$BACKUP" -mindepth 1 -print -quit | grep -q .; then
    echo "backup: $BACKUP"
else
    rmdir "$BACKUP"
fi

# ---------------------------------------------------------------------------
# Remove configs antigas
#
# Importante:
# todas as validações necessárias aconteceram antes desta etapa.
# ---------------------------------------------------------------------------

stow \
    -n \
    -R \
    -d "$DOTFILES" \
    -t "$HOME" \
    "${PACKAGES[@]}" ||
    {
        echo "setup.sh: simulação do Stow falhou; nada foi removido." >&2
        exit 1
    }

for target in "${TARGETS[@]}"; do
    rm -rf "$HOME/$target"
done

# ---------------------------------------------------------------------------
# Wallpapers
# ---------------------------------------------------------------------------

install -Dm644 \
    "$DOTFILES/images/Remielle.png" \
    "$HOME/Pictures/Wallpapers/Remielle.png"

install -Dm644 \
    "$DOTFILES/images/Eblana.jpg" \
    "$HOME/Pictures/Icons/Eblana.jpg"

# ---------------------------------------------------------------------------
# Stow
# ---------------------------------------------------------------------------

stow \
    -R \
    -d "$DOTFILES" \
    -t "$HOME" \
    "${PACKAGES[@]}"

# ---------------------------------------------------------------------------
# Yazi file chooser wrapper
# ---------------------------------------------------------------------------

WRAPPER="$DOTFILES/xdg/.config/xdg-desktop-portal-termfilechooser/yazi-wrapper.sh"

chmod +x "$WRAPPER"

# ---------------------------------------------------------------------------
# Serviços de usuário
# ---------------------------------------------------------------------------

if command -v systemctl >/dev/null 2>&1; then

    systemctl --user stop \
        xdg-desktop-portal-termfilechooser.service \
        2>/dev/null || true

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

# ---------------------------------------------------------------------------
# Noctalia
# ---------------------------------------------------------------------------

if command -v noctalia >/dev/null 2>&1; then
    noctalia msg config-reload \
        2>/dev/null || true
fi

echo
echo "done - run 'exec fish' to reload your shell"
