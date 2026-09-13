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

## Fresh machine

Requires: `git`, `stow`.

```sh
git clone <repo-url> ~/.dotfiles
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

## Notes

- `fish_variables` and OpenTabletDriver's stale `Settings.json` are
  intentionally **not** versioned (machine-generated state); the live copies
  stay as regular files. `fish` recreates its variables file on its own.
- Machine-specific secrets are excluded: Sunshine credentials/state, OpenRGB
  logs, OpenTabletDriver logs/plugin binaries, faugus-launcher prefixes and
  its API key, niri `*.backup*`.
- Noctalia-generated theme files and upstream-vendored assets
  (`modernz.lua`, yazi flavor `tmtheme.xml`, plugin sources) are versioned
  as-is and left untouched by cleanup passes.
- Niri config is split by topic under `niri/.config/niri/cfg/`
  (`startup`, `input`, `binds`, `appearance`, `outputs`, `rules`, `system`);
  validate with `niri validate` after changes.
- Never restart `niri.service`, `gnome-keyring-daemon`, or the polkit agent
  from scripts — that kills or breaks the running session.
