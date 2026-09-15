# dotfiles

GNU Stow-managed dotfiles. Each top-level directory is a Stow package that
links its `.config/...` tree into `$HOME`.

## Packages

| Package | Target |
|---|---|
| btop | `~/.config/btop` |
| fastfetch | `~/.config/fastfetch` |
| fish | `~/.config/fish` |
| gtk | `~/.config/gtk-3.0`, `~/.config/gtk-4.0` (`settings.ini` only; `gtk.css`/`noctalia.css` are Noctalia-generated) |
| kitty | `~/.config/kitty` |
| libreoffice | `~/.config/libreoffice` (dotfiles pending) |
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

## Install packages

```sh
sudo pacman -S adw-gtk-theme btop fastfetch fish fisher git jq kitty lib32-mangohud libreoffice-fresh mangohud mpv niri noctalia noctalia-greeter noto-fonts openrgb opentabletdriver papirus-icon-theme pavucontrol pipewire pipewire-alsa pipewire-jack pipewire-pulse stow sunshine ttf-ibm-plex ttf-jetbrains-mono-nerd wireplumber xdg-desktop-portal xdg-desktop-portal-gtk yazi zed
```

```sh
paru -S bibata-cursor-theme-bin xdg-desktop-portal-termfilechooser-hunkyburrito-git
```

## Look & feel

* GTK3 theme: `adw-gtk3-dark`
* GTK4 theme: `Adwaita`
* Icons: `Papirus-Dark`
* Cursor: `Bibata-Modern-Ice`
* Font: `IBM Plex Sans`
* Terminal font: `JetBrains Mono Nerd`

## Plugins and extensions

* fish — [pure](https://github.com/pure-fish/pure), [autopair](https://github.com/jorgebucaran/autopair.fish), [done](https://github.com/franciscolourenco/done).
* yazi — [full-border](https://github.com/yazi-rs/plugins/tree/main/full-border.yazi), [mount](https://github.com/yazi-rs/plugins/tree/main/mount.yazi).
* mpv — [ModernZ](https://github.com/Samillion/ModernZ).

## Noctalia templates (enabled in `noctalia/config.toml`)

* Builtin (6): `btop`, `gtk3`, `gtk4`, `kitty`, `niri`, `qt`.
* Community (10): `opencode`, `pywalfox-beta4`, `discord`, `prismlauncher`, `steam`, `zed`, `libreoffice`, `gimp`, `fastfetch`, `yazi`.
* Generated outputs are not tracked.

## Installation

```sh
git clone https://github.com/carlosmrd/dotfiles ~/.dotfiles
cd ~/.dotfiles
./setup.sh
exec fish
```

`setup.sh` is idempotent (safe to re-run) and does, in order:

1. Backs up live files that are **not** tracked in this repo
   (`fish_variables`, Sunshine credentials/state, OpenTabletDriver's stale
   `Settings.json`, logs, plugin dirs, niri `*.backup*`) to
   `~/.dotfiles-backup/<timestamp>/` — prune old backups yourself.
2. Wipes the 19 app config dirs owned by the packages below.
3. Copies `images/` to `~/Pictures/Wallpapers` and `~/Pictures/Icons`.
4. Restows all packages (`stow -R`) into `$HOME`.
5. Makes the termfilechooser `yazi-wrapper.sh` executable.
6. Restarts the portal stack, `pipewire` / `pipewire-pulse` / `wireplumber`,
   and `opentabletdriver` (every call guarded — missing units never abort it).
7. Reloads noctalia (`noctalia msg config-reload`, no session kill).

## Post-install plugins (run after `setup.sh`)

fisher needs fish; `ya pkg install` needs the stowed `~/.config/yazi/package.toml`:

```sh
fisher install pure-fish/pure jorgebucaran/autopair.fish franciscolourenco/done
```

```sh
ya pkg install
```

### Apply GTK settings

```sh
gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'
gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
gsettings set org.gnome.desktop.interface font-name 'IBM Plex Sans 11'
gsettings set org.gnome.desktop.interface cursor-theme 'Bibata-Modern-Ice'
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
```
