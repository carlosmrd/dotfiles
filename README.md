# dotfiles

GNU Stow-managed dotfiles. Each top-level directory is a Stow package that
links its `.config/...` tree into `$HOME`.

## Packages

| Package | Target |
|---|---|
| btop | `~/.config/btop` |
| fastfetch | `~/.config/fastfetch` |
| fish | `~/.config/fish` |
| kitty | `~/.config/kitty` |
| mangohud | `~/.config/MangoHud` |
| mpv | `~/.config/mpv` |
| niri | `~/.config/niri` |
| noctalia | `~/.config/noctalia` |
| openrgb | `~/.config/OpenRGB` |
| opentabletdriver | `~/.config/OpenTabletDriver` |
| pipewire | `~/.config/pipewire` |
| sunshine | `~/.config/sunshine` |
| wireplumber | `~/.config/wireplumber` |
| xdg | `~/.config/xdg-desktop-portal*` |
| yazi | `~/.config/yazi` |
| zed | `~/.config/zed` |

## Installation

Requires: `git`, `stow`.

```sh
git clone https://github.com/carlosmrd/dotfiles ~/.dotfiles
cd ~/.dotfiles
./setup.sh
exec fish
```

`setup.sh` is idempotent (safe to re-run) and does, in order:

1. Copies `images/` to `~/Pictures/Wallpapers` and `~/Pictures/Icons`.
2. Restows all packages (`stow -R`) into `$HOME`.
3. Makes the termfilechooser `yazi-wrapper.sh` executable.
4. Restarts the portal stack, `pipewire` / `pipewire-pulse` / `wireplumber`,
   and `opentabletdriver` (every call guarded — missing units never abort it).
5. Reloads noctalia (`noctalia msg config-reload`, no session kill).
