# dotfiles

GNU Stow-managed dotfiles. Each top-level directory is a Stow package that
links its `.config/...` tree into `$HOME`.

## Packages

| Package | Target |
|---|---|
| btop | `~/.config/btop` |
| fastfetch | `~/.config/fastfetch` |
| fish | `~/.config/fish` |
| gtk | `~/.config/gtk-3.0`, `~/.config/gtk-4.0` |
| kitty | `~/.config/kitty` |
| libreoffice | (not stowed — local profile only; `libreoffice-fresh` installed via pacman for the Noctalia template) |
| mangohud | `~/.config/MangoHud` |
| mpv | `~/.config/mpv` |
| niri | `~/.config/niri` |
| noctalia | `~/.config/noctalia` |
| openrgb | `~/.config/OpenRGB` |
| opentabletdriver | `~/.config/OpenTabletDriver` |
| pipewire | `~/.config/pipewire` |
| sunshine | `~/.config/sunshine` |
| wireplumber | `~/.config/wireplumber` |
| xdg | `~/.config/xdg-desktop-portal` |
| zed | `~/.config/zed` |

> System packages (`pacman` + one AUR package) are installed automatically
> by `setup.sh` — see `PACMAN_PKGS` in the script. No manual installing.

## Look & feel

* GTK3 theme: `adw-gtk3-dark`
* GTK4 theme: `Adwaita`
* Icons: `Papirus-Dark`
* Cursor: `Bibata-Modern-Ice`
* Font: `IBM Plex Sans`
* Terminal font: `JetBrains Mono Nerd`

## Plugins and extensions

* fish — [pure](https://github.com/pure-fish/pure), [autopair](https://github.com/jorgebucaran/autopair.fish), [done](https://github.com/franciscolourenco/done).
* mpv — [ModernZ](https://github.com/Samillion/ModernZ).

## Noctalia templates (enabled in `noctalia/config.toml`)

* Builtin (6): `btop`, `gtk3`, `gtk4`, `kitty`, `niri`, `qt`.
* Community (8): `opencode`, `discord`, `prismlauncher`, `steam`, `zed`, `libreoffice`, `gimp`, `zen-browser`.
* Generated outputs are not tracked.

## Installation

```sh
git clone https://github.com/carlosmrd/dotfiles ~/.dotfiles
cd ~/.dotfiles
./setup.sh
```

Then log out and back in (applies the default shell).

`setup.sh` is idempotent (safe to re-run) and does, in order:

1. Installs system packages (`sudo pacman -S --needed`, AUR via `paru -S --needed`; skipped gracefully when unavailable).
2. Backs up every managed `~/.config` dir that is about to be wiped
   (whole dirs, symlinks back into this repo excluded) to
   `~/.dotfiles-backup/<timestamp>/` — prune old backups yourself.
3. Wipes the 17 app config dirs owned by the packages below.
4. Copies `images/Icons/*` to `~/Pictures/Icons` and `images/Wallpapers/*` to `~/Pictures/Wallpapers` (plain copies, not Stow-managed).
5. Restows all packages (`stow -R`) into `$HOME`.
6. Restarts the portal stack, `pipewire` / `pipewire-pulse` / `wireplumber`,
   and `opentabletdriver` (every call guarded — missing units never abort it).
7. Reloads noctalia (`noctalia msg config-reload`, no session kill) and
   regenerates template outputs (`noctalia msg templates-apply`; outputs are
   not tracked in git).
8. Installs fisher plugins (`pure`, `autopair`, `done`; skipped if fisher is missing).
9. Applies GTK settings via `gsettings` (skipped if `gsettings` is missing).
10. Sets fish as the default shell via `chsh` (skipped if already set or if `fish`/`chsh` is missing; takes effect on next login).

## Post-install (automatic in `setup.sh`, manual fallback below)

```sh
fisher install pure-fish/pure jorgebucaran/autopair.fish franciscolourenco/done
```

### Apply GTK settings

```sh
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
gsettings set org.gnome.desktop.interface font-name 'IBM Plex Sans 11'
gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Ice'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
```
