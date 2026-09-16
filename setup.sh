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

# ---------------------------------------------------------------------------
# Pacotes Stow
# ---------------------------------------------------------------------------

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

if ! STOW_CHECK="$(stow -n -R -d "$DOTFILES" -t "$HOME" "${PACKAGES[@]}" 2>&1)"; then
    UNRESOLVED=0
    SEEN_CONFLICT=0

    while IFS= read -r line; do
        case "$line" in
            *"existing target "*)
                SEEN_CONFLICT=1
                rest="${line##*existing target }"
                conflict="${rest%% *}"

                covered=0

                for t in "${TARGETS[@]}"; do
                    if [[ "$conflict" == "$t" || "$conflict" == "$t/"* ]]; then
                        covered=1
                        break
                    fi
                done

                if [[ "$covered" -eq 0 ]]; then
                    echo "setup.sh: conflito fora dos dirs gerenciados: $conflict" >&2
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
        echo "setup.sh: simulação do Stow falhou; nada foi removido." >&2
        exit 1
    fi

    echo "setup.sh: conflitos sob dirs gerenciados serão resolvidos pela recriação."
fi

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
# Serviços de usuário
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Noctalia
# ---------------------------------------------------------------------------

if command -v noctalia >/dev/null 2>&1; then
    noctalia msg config-reload \
        2>/dev/null || true
fi

echo
echo "done - run 'exec fish' to reload your shell"
