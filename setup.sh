#!/usr/bin/env bash
# Fresh-machine bootstrap: backup, wipe, images, stow links, service refresh.
# Idempotent: safe to re-run. Never fails on missing services.
set -euo pipefail

DOTFILES="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -n "${HOME:-}" ] && [ -d "$HOME" ] || { echo "setup.sh: bad HOME" >&2; exit 1; }
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

PACKAGES=(
  btop fastfetch fish kitty mangohud mpv niri noctalia
  openrgb opentabletdriver pipewire sunshine wireplumber xdg yazi zed
)

# App config dirs owned by the packages above (wiped before stowing).
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

# Backup live files NOT tracked in the repo (wiped below, must not be lost).
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
for src in "${KEEP[@]}"; do
  [ -e "$src" ] || [ -L "$src" ] || continue
  rel="${src#$HOME/}"
  mkdir -p "$BACKUP/$(dirname "$rel")"
  cp -a "$src" "$BACKUP/$rel"
done
[ -d "$BACKUP" ] && echo "backup: $BACKUP"

# Wipe
for t in "${TARGETS[@]}"; do
  rm -rf "$HOME/$t"
done

# Images
install -Dm644 "$DOTFILES/images/Remielle.png" "$HOME/Pictures/Wallpapers/Remielle.png"
install -Dm644 "$DOTFILES/images/Eblana.jpg" "$HOME/Pictures/Icons/Eblana.jpg"

# Stow
command -v stow >/dev/null || { echo "setup.sh: stow not installed" >&2; exit 1; }
stow -R -d "$DOTFILES" -t "$HOME" "${PACKAGES[@]}"

# Wrapper
chmod +x "$DOTFILES/xdg/.config/xdg-desktop-portal-termfilechooser/yazi-wrapper.sh"

# Services
if command -v systemctl >/dev/null; then
  # Portals
  systemctl --user stop xdg-desktop-portal-termfilechooser.service 2>/dev/null || true
  systemctl --user stop xdg-desktop-portal.service 2>/dev/null || true
  systemctl --user start xdg-desktop-portal.service 2>/dev/null || true

  # Audio
  for u in pipewire.service pipewire-pulse.service wireplumber.service; do
    systemctl --user restart "$u" 2>/dev/null || true
  done

  # Tablet
  systemctl --user restart opentabletdriver.service 2>/dev/null || true
fi

# Shell
noctalia msg config-reload 2>/dev/null || true

echo "done - run 'exec fish' to reload your shell"
