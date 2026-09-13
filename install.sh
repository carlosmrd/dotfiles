#!/usr/bin/env bash
set -euo pipefail
DOTFILES="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
if [[ "${EUID}" -eq 0 ]]; then
  echo "install.sh: rode como usuário normal com sudo, não como root." >&2
  exit 1
fi
TARGET_USER="${SUDO_USER:-$USER}"
TARGET_UID="$(id -u "$TARGET_USER")"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$TARGET_UID}"
log()  { printf '\033[1;32m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m-->\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
command -v sudo >/dev/null || die "sudo não encontrado"
sudo -v
SUDO_KEEPALIVE_PID=""
if sudo -n true 2>/dev/null; then
  ( while kill -0 $$ 2>/dev/null; do sleep 60; sudo -n true 2>/dev/null || true; done ) &
  SUDO_KEEPALIVE_PID=$!
  trap '[[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
fi
ISA_PREVIEW="x86-64-v3"
if /lib/ld-linux-x86-64.so.2 --help 2>/dev/null | grep -q "x86-64-v4 (supported, searched)"; then
  ISA_PREVIEW="x86-64-v4"
fi
GPU_PREVIEW="$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -n1 || true)"
[[ -z "$GPU_PREVIEW" ]] && GPU_PREVIEW="GPU não detectada"
cat <<EOF
install.sh — resumo (nada foi alterado ainda):
  usuário-alvo (greeter/docker/user-services): $TARGET_USER
  CPU ISA CachyOS: $ISA_PREVIEW | GPU: $GPU_PREVIEW
  vai fazer: habilitar multilib + repos CachyOS, instalar paru,
    blocos pacman + AUR (--skipreview, sem pausa),
    greetd como DM (desabilita sddm/gdm/lightdm/ly; sobrescreve config.toml),
    greeter.toml niri + cursor Adwaita,
    UFW padrão + SSH (só-chave se houver authorized_keys),
    headers do kernel em uso, services system/user, stow via setup.sh.
  setup.sh APAGA 17 dirs de config e recria via stow (só KEEP tem backup).
  UFW reset apaga regras atuais (backup .bak); sem drivers de GPU (manual).
  reboot recomendado ao final (greetd).
EOF
read -rp "ENTER para começar unattended (Ctrl-C cancela)... " _
PACMAN_CONF="/etc/pacman.conf"
GREETD_CONF="/etc/greetd/config.toml"
GREETER_DIR="/var/lib/noctalia-greeter"
GREETER_TOML="$GREETER_DIR/greeter.toml"
backup_once() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  [[ -f "$f.bak" ]] && return 0
  sudo cp -a "$f" "$f.bak"
  log "backup: $f -> $f.bak"
}
log "habilitando multilib em $PACMAN_CONF"
backup_once "$PACMAN_CONF"
sudo sed -i 's/^#\[multilib\]/[multilib]/' "$PACMAN_CONF"
sudo sed -i '/^\[multilib\]/{n;s/^#Include =/Include =/}' "$PACMAN_CONF"
grep -A1 '^\[multilib\]' "$PACMAN_CONF" || warn "bloco [multilib] não encontrado"
if grep -qE '^\[cachyos' "$PACMAN_CONF"; then
  log "repos CachyOS já presentes em $PACMAN_CONF"
else
  log "adicionando repos CachyOS ao Arch vanilla"
  if ! sudo timeout 60 pacman-key --recv-keys F3B607488DB35A47 --keyserver keyserver.ubuntu.com; then
    if ! sudo timeout 60 pacman-key --recv-keys F3B607488DB35A47 --keyserver keys.openpgp.org; then
      die "falha ao receber chave CachyOS nos dois keyservers"
    fi
  fi
  sudo pacman-key --lsign-key F3B607488DB35A47
  command -v curl >/dev/null || sudo pacman -S --needed --noconfirm curl
  MIRROR="https://mirror.cachyos.org/repo/x86_64/cachyos"
  LISTING="$(curl -fsSL "$MIRROR/" 2>/dev/null || true)"
  KEYRING_PKG="cachyos-keyring-20240331-1-any.pkg.tar.zst"
  MIRRORLIST_PKG="cachyos-mirrorlist-27-1-any.pkg.tar.zst"
  V3_PKG="cachyos-v3-mirrorlist-27-1-any.pkg.tar.zst"
  V4_PKG="cachyos-v4-mirrorlist-27-1-any.pkg.tar.zst"
  FOUND_KEYRING="$(echo "$LISTING" | grep -oE 'cachyos-keyring-[^"<> ]*pkg\.tar\.zst' | sort -u | tail -n1 || true)"
  if [[ -n "$FOUND_KEYRING" ]]; then
    KEYRING_PKG="$FOUND_KEYRING"
  fi
  FOUND_MIRRORLIST="$(echo "$LISTING" | grep -oE 'cachyos-mirrorlist-[^"<> ]*pkg\.tar\.zst' | sort -u | tail -n1 || true)"
  if [[ -n "$FOUND_MIRRORLIST" ]]; then
    MIRRORLIST_PKG="$FOUND_MIRRORLIST"
  fi
  FOUND_V3="$(echo "$LISTING" | grep -oE 'cachyos-v3-mirrorlist-[^"<> ]*pkg\.tar\.zst' | sort -u | tail -n1 || true)"
  if [[ -n "$FOUND_V3" ]]; then
    V3_PKG="$FOUND_V3"
  fi
  FOUND_V4="$(echo "$LISTING" | grep -oE 'cachyos-v4-mirrorlist-[^"<> ]*pkg\.tar\.zst' | sort -u | tail -n1 || true)"
  if [[ -n "$FOUND_V4" ]]; then
    V4_PKG="$FOUND_V4"
  fi
  sudo pacman -U --noconfirm --needed \
    "$MIRROR/$KEYRING_PKG" \
    "$MIRROR/$MIRRORLIST_PKG" \
    "$MIRROR/$V3_PKG" \
    "$MIRROR/$V4_PKG"
  ISA_V4=1; /lib/ld-linux-x86-64.so.2 --help 2>/dev/null | grep -q "x86-64-v4 (supported, searched)" && ISA_V4=0 || true
  {
    echo ""
    if [[ "$ISA_V4" -eq 0 ]]; then
      echo "[cachyos-v4]"
      echo "Include = /etc/pacman.d/cachyos-v4-mirrorlist"
      echo ""
      echo "[cachyos-core-v4]"
      echo "Include = /etc/pacman.d/cachyos-v4-mirrorlist"
      echo ""
      echo "[cachyos-extra-v4]"
      echo "Include = /etc/pacman.d/cachyos-v4-mirrorlist"
      echo ""
    else
      echo "[cachyos-v3]"
      echo "Include = /etc/pacman.d/cachyos-v3-mirrorlist"
      echo ""
      echo "[cachyos-core-v3]"
      echo "Include = /etc/pacman.d/cachyos-v3-mirrorlist"
      echo ""
      echo "[cachyos-extra-v3]"
      echo "Include = /etc/pacman.d/cachyos-v3-mirrorlist"
      echo ""
    fi
    echo "[cachyos]"
    echo "Include = /etc/pacman.d/cachyos-mirrorlist"
  } | sudo tee -a "$PACMAN_CONF" >/dev/null
  log "repos CachyOS adicionados (backup em $PACMAN_CONF.bak)"
fi
log "sincronizando bases"
sudo pacman -Sy
if command -v paru >/dev/null; then
  log "paru já instalado: $(paru --version | head -n1)"
else
  log "instalando paru"
  if sudo pacman -S --needed --noconfirm paru; then
    log "paru via repo CachyOS/Arch"
  else
    warn "paru não está nos repos — compilando via AUR (precisa base-devel+git)"
    sudo pacman -S --needed --noconfirm base-devel git
    tmp="$(mktemp -d)"
    git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
    if (cd "$tmp/paru-bin" && makepkg -si --noconfirm --needed); then
      rm -rf "$tmp"
    else
      rm -rf "$tmp"
      die "falha ao compilar paru-bin"
    fi
  fi
fi
KERN_REL="$(uname -r)"
KERN_HEADERS="linux-headers"
if [[ "$KERN_REL" == *cachyos* ]]; then
  KERN_HEADERS="linux-cachyos-headers"
elif [[ "$KERN_REL" == *lts* ]]; then
  KERN_HEADERS="linux-lts-headers"
elif [[ "$KERN_REL" == *zen* ]]; then
  KERN_HEADERS="linux-zen-headers"
fi
BASE_PKGS=(
  wpa_supplicant networkmanager ufw ufw-extras openssh reflector
  nano vim git stow wget htop which xdg-utils curl
  pciutils
  pipewire pipewire-pulse pipewire-alsa pipewire-jack wireplumber pavucontrol playerctl
  libsecret gnome-keyring polkit-gnome polkit
  ananicy-cpp cachyos-ananicy-rules bpftune-git
  bluez bluez-utils bluez-hid2hci bluez-libs bluez-obex
  avahi cups
  systemd-timesyncd systemd-resolved
  python python-pip rust go tailscale
  jdk-openjdk nodejs npm pnpm
  docker docker-buildx docker-compose
  niri greetd noctalia noctalia-greeter
  unzip unrar snapper
  base-devel "$KERN_HEADERS"
  fish eza bat expac jq libnotify
  cachyos-rate-mirrors
  xdg-desktop-portal xdg-desktop-portal-gtk accountsservice
  gamemode lib32-gamemode lib32-vulkan-icd-loader lib32-mangohud
  vulkan-icd-loader vulkan-tools 7zip
  noto-fonts ttf-jetbrains-mono-nerd
)
APP_PKGS=(
  btop fastfetch kitty mpv firefox sbctl
  steam discord spotify-launcher gimp protonplus faugus-launcher
  moonlight-qt sunshine qview btrfs-assistant opentabletdriver openrgb opencode
  gamescope goverlay mangohud limine-snapper-sync zed libreoffice-fresh qbittorrent yazi
  wine wine-mono wine-gecko winetricks umu-launcher protontricks
)
GPU_LINE="$(lspci 2>/dev/null | grep -iE 'vga|3d|display' | head -n1 || true)"
if [[ -n "$GPU_LINE" ]]; then
  log "GPU: $GPU_LINE (drivers de GPU não instalados por este script)"
else
  warn "GPU não detectada via lspci (drivers de GPU não instalados por este script)"
fi
log "instalando pacotes base+complementos (${#BASE_PKGS[@]})"
if ! sudo pacman -S --needed --noconfirm "${BASE_PKGS[@]}"; then
  warn "bulk base falhou — tentando pacote a pacote"
  for p in "${BASE_PKGS[@]}"; do
    sudo pacman -S --needed --noconfirm "$p" || warn "falha ao instalar $p"
  done
fi
log "instalando pacotes apps (${#APP_PKGS[@]})"
if ! sudo pacman -S --needed --noconfirm "${APP_PKGS[@]}"; then
  warn "bulk apps falhou — tentando pacote a pacote"
  for p in "${APP_PKGS[@]}"; do
    sudo pacman -S --needed --noconfirm "$p" || warn "falha ao instalar $p"
  done
fi
AUR_PKGS=(
  arch-update
  eden-bin
  xdg-desktop-portal-termfilechooser-hunkyburrito-git
  fish-done
)
log "instalando AUR via paru (${#AUR_PKGS[@]}) — sem review (unattended)"
export PARU_SKIP_REVIEW=1
if ! paru -S --needed --noconfirm --skipreview --cleanafter "${AUR_PKGS[@]}"; then
  warn "bulk AUR falhou — tentando pacote a pacote"
  for p in "${AUR_PKGS[@]}"; do
    paru -S --needed --noconfirm --skipreview --cleanafter "$p" || warn "falha ao instalar $p"
  done
fi
log "definindo greetd como display manager"
for dm in sddm gdm lightdm ly lxdm; do
  if systemctl is-enabled "$dm.service" >/dev/null 2>&1; then
    warn "desabilitando $dm"
    sudo systemctl --no-ask-password --no-pager disable "$dm.service" --now 2>/dev/null || true
  fi
done
sudo getent group video >/dev/null && sudo usermod -aG video greeter 2>/dev/null || true
sudo getent group input >/dev/null && sudo usermod -aG input greeter 2>/dev/null || true
sudo systemctl --no-ask-password --no-pager enable greetd.service
SESSION_BIN="$(command -v noctalia-greeter-session || echo /usr/bin/noctalia-greeter-session)"
log "noctalia-greeter-session em: $SESSION_BIN"
if [[ ! -x "$SESSION_BIN" ]]; then
  die "noctalia-greeter-session não encontrado — pacote noctalia-greeter falhou?"
fi
log "escrevendo $GREETD_CONF (sessão niri, usuário $TARGET_USER)"
backup_once "$GREETD_CONF"
sudo mkdir -p "$(dirname "$GREETD_CONF")"
sudo tee "$GREETD_CONF" >/dev/null <<EOF
[terminal]
vt = 1

[default_session]
command = "$SESSION_BIN -- --session niri --user $TARGET_USER"
user = "greeter"
EOF
log "configurando $GREETER_TOML (cursor Adwaita, restante segue seu niri)"
sudo mkdir -p "$GREETER_DIR"
sudo tee "$GREETER_TOML" >/dev/null <<EOF
[session]
default = "niri"

[user]
default = "$TARGET_USER"

[appearance]
scheme = "Synced"

[cursor]
theme = "Adwaita"
size = 24

[keyboard]
numlock = true
EOF
sudo chown -R greeter:greeter "$GREETER_DIR"
sudo chmod 755 "$GREETER_DIR"
sudo chmod 644 "$GREETER_TOML"
log "conferindo PAM do greetd p/ gnome-keyring"
if [[ -f /etc/pam.d/greetd ]]; then
  if ! grep -q pam_gnome_keyring /etc/pam.d/greetd; then
    warn "/etc/pam.d/greetd sem pam_gnome_keyring — adicionando (backup .bak)"
    backup_once /etc/pam.d/greetd
    echo "-auth       optional      pam_gnome_keyring.so" | sudo tee -a /etc/pam.d/greetd >/dev/null
    echo "-session    optional      pam_gnome_keyring.so auto_start" | sudo tee -a /etc/pam.d/greetd >/dev/null
  fi
else
  warn "/etc/pam.d/greetd não existe — greetd criará no install; keyring via startup.kdl continua valendo"
fi
sudo loginctl enable-linger "$TARGET_USER" 2>/dev/null || true
sudo -u "$TARGET_USER" systemctl --user --no-ask-password --no-pager enable gnome-keyring-daemon.socket 2>/dev/null || true
SYS_SERVICES=(
  NetworkManager ufw sshd bluetooth
  ananicy-cpp bpftune
  tailscaled docker docker.socket
  systemd-timesyncd systemd-resolved
  avahi-daemon cups cups.socket
)
SYS_TIMERS=(
  cachyos-rate-mirrors.timer
  snapper-timeline.timer snapper-cleanup.timer
  fstrim.timer
)
log "habilitando serviços de sistema"
for s in "${SYS_SERVICES[@]}"; do
  sudo systemctl --no-ask-password --no-pager enable --now "$s" 2>/dev/null || warn "falha ao habilitar $s"
done
if systemctl is-enabled tlp.service >/dev/null 2>&1 || systemctl is-enabled auto-cpufreq.service >/dev/null 2>&1; then
  warn "tlp/auto-cpufreq ativo — pulando power-profiles-daemon (conflito)"
else
  sudo systemctl --no-ask-password --no-pager enable --now power-profiles-daemon 2>/dev/null || warn "falha ao habilitar power-profiles-daemon"
fi
for t in "${SYS_TIMERS[@]}"; do
  sudo systemctl --no-ask-password --no-pager enable --now "$t" 2>/dev/null || warn "timer $t indisponível (ok em Arch puro)"
done
if systemctl list-unit-files 2>/dev/null | grep -q '^reflector\.timer'; then
  sudo systemctl --no-ask-password --no-pager enable --now reflector.timer 2>/dev/null || true
fi
if systemctl list-unit-files 2>/dev/null | grep -q 'limine-snapper-sync'; then
  sudo systemctl --no-ask-password --no-pager enable --now limine-snapper-sync.service 2>/dev/null || warn "limine-snapper-sync indisponível"
fi
if systemctl list-unit-files 2>/dev/null | grep -q 'limine-snapper-watcher'; then
  sudo systemctl --no-ask-password --no-pager enable --now limine-snapper-watcher.service 2>/dev/null || true
fi
sudo snapper -c root list 2>/dev/null || sudo snapper -c root create-config / 2>/dev/null || true
sudo usermod -aG docker "$TARGET_USER" 2>/dev/null || true
log "habilitando serviços de usuário (pipewire/wireplumber/playerctld/tablet)"
sudo -u "$TARGET_USER" systemctl --user --no-ask-password --no-pager enable \
  pipewire.socket pipewire-pulse.socket wireplumber.service \
  playerctld.service opentabletdriver.service 2>/dev/null \
  || warn "falha ao habilitar user-services (re-rode logado)"
sudo -u "$TARGET_USER" systemctl --user --no-ask-password --no-pager start \
  pipewire-pulse.socket wireplumber.service playerctld.service 2>/dev/null || true
sudo -u "$TARGET_USER" systemctl --user --no-ask-password --no-pager enable app-dev.lizardbyte.app.Sunshine.service 2>/dev/null || true
if sudo -u "$TARGET_USER" systemctl --user list-unit-files 2>/dev/null | grep -q 'arch-update.timer'; then
  sudo -u "$TARGET_USER" systemctl --user --no-ask-password --no-pager enable --now arch-update.timer 2>/dev/null || true
fi
log "aplicando UFW padrão (deny in / allow out / allow ssh)"
backup_once /etc/ufw/user.rules
backup_once /etc/ufw/user6.rules
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw --force enable
sudo systemctl --no-ask-password --no-pager enable --now ufw
if systemctl is-active docker.service >/dev/null 2>&1; then
  sudo systemctl --no-ask-password --no-pager restart docker 2>/dev/null || true
fi
log "configurando sshd (só-chave se houver authorized_keys)"
SSHD_CONF="/etc/ssh/sshd_config.d/10-hardened.conf"
backup_once /etc/ssh/sshd_config
sudo mkdir -p /etc/ssh/sshd_config.d
USER_HOME="$(eval echo "~$TARGET_USER")"
if sudo -u "$TARGET_USER" test -f "$USER_HOME/.ssh/authorized_keys"; then
  sudo tee "$SSHD_CONF" >/dev/null <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
X11Forwarding no
EOF
  sudo sshd -t || die "sshd -t falhou após escrever $SSHD_CONF"
  sudo systemctl --no-ask-password --no-pager enable --now sshd
else
  sudo tee "$SSHD_CONF" >/dev/null <<'EOF'
PermitRootLogin no
X11Forwarding no
EOF
  sudo sshd -t || die "sshd -t falhou após escrever $SSHD_CONF"
  sudo systemctl --no-ask-password --no-pager enable --now sshd
  warn "sem $USER_HOME/.ssh/authorized_keys — mantido login por senha; adicione a chave e re-rode"
fi
if pacman -Q fish-done >/dev/null 2>&1; then
  log "done.fish OK (pacote fish-done $(pacman -Q fish-done | cut -d' ' -f2))"
else
  warn "fish-done ausente — bloco AUR falhou p/ fish-done?"
fi
log "rodando setup.sh do repo (stow + portais + áudio)"
bash "$DOTFILES/setup.sh"
cat <<EOF

Concluído. Próximos passos manuais:
  1. Sync greeter<->noctalia: abra Noctalia Settings → Security → Noctalia Greeter → Sync Now
     (requer polkit/pkexec + accountsservice, já instalados), depois: sudo systemctl restart greetd
  2. sbctl: Secure Boot é manual (sbctl status / enroll). sunshine tailscale: 'tailscale up' manual.
  3. Drivers de GPU não instalados por este script — instale manualmente p/ sua GPU.
  4. Reboot recomendado (greetd): sudo reboot
  5. Depois: exec fish

Verificação rápida:
  pacman -Q paru niri noctalia-greeter fish-done
  systemctl is-enabled greetd ufw sshd bluetooth docker tailscaled
  systemctl --user is-enabled playerctld wireplumber
  cat $GREETD_CONF
EOF
