#!/usr/bin/env bash
# Fresh-machine bootstrap: images, stow links, portal + audio refresh.
# Idempotent: safe to re-run. Never fails on missing services.
set -euo pipefail

DOTFILES="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Images
install -Dm644 "$DOTFILES/images/Remielle.png" "$HOME/Pictures/Wallpapers/Remielle.png"
install -Dm644 "$DOTFILES/images/Eblana.jpg" "$HOME/Pictures/Icons/Eblana.jpg"

# Stow
command -v stow >/dev/null || { echo "setup.sh: stow not installed" >&2; exit 1; }
stow -R -d "$DOTFILES" -t "$HOME" \
  btop fastfetch fish kitty mangohud mpv niri noctalia \
  openrgb opentabletdriver pipewire sunshine wireplumber xdg yazi zed

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
