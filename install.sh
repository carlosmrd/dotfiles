#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

if [[ "${EUID}" -eq 0 ]]; then
    echo "install.sh: rode como usuário normal com sudo, não como root." >&2
    exit 1
fi

TARGET_USER="${SUDO_USER:-$USER}"
TARGET_UID="$(id -u "$TARGET_USER")"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

if [[ -z "$TARGET_HOME" || ! -d "$TARGET_HOME" ]]; then
    echo "install.sh: não foi possível determinar HOME de $TARGET_USER." >&2
    exit 1
fi

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$TARGET_UID}"

log()  { printf '\033[1;32m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m-->\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

command -v sudo >/dev/null || die "sudo não encontrado."
command -v pacman >/dev/null || die "pacman não encontrado."
command -v systemctl >/dev/null || die "systemctl não encontrado."
command -v getent >/dev/null || die "getent não encontrado."

sudo -v

SUDO_KEEPALIVE_PID=""
if sudo -n true 2>/dev/null; then
    (
        while kill -0 $$ 2>/dev/null; do
            sleep 60
            sudo -n true 2>/dev/null || true
        done
    ) &
    SUDO_KEEPALIVE_PID=$!
    trap '[[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT
fi

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

package_installed() {
    pacman -Q "$1" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Pré-validação
# ---------------------------------------------------------------------------

[[ -d "$DOTFILES" ]] || die "diretório do repositório não encontrado: $DOTFILES"
[[ -f "$DOTFILES/setup.sh" ]] || die "setup.sh não encontrado em $DOTFILES"
[[ -d "$DOTFILES/images" ]] || die "diretório images/ não encontrado."

[[ -f "$DOTFILES/images/Remielle.png" ]] \
    || die "imagem ausente: $DOTFILES/images/Remielle.png"

[[ -f "$DOTFILES/images/Eblana.jpg" ]] \
    || die "imagem ausente: $DOTFILES/images/Eblana.jpg"

for pkg in \
    btop fastfetch fish kitty mangohud mpv niri noctalia \
    openrgb opentabletdriver pipewire sunshine wireplumber \
    xdg yazi zed
do
    [[ -d "$DOTFILES/$pkg" ]] \
        || die "pacote Stow ausente no repositório: $pkg"
done

cat <<EOF
install.sh — resumo

  usuário-alvo:
    $TARGET_USER

  home:
    $TARGET_HOME

  repositório:
    $DOTFILES

  vai fazer:
    - habilitar multilib
    - instalar ferramentas iniciais
    - configurar repositórios CachyOS
    - detectar ISA da CPU
    - atualizar completamente o sistema
    - instalar pacotes obrigatórios
    - instalar pacotes opcionais
    - instalar AUR via paru
    - configurar greetd + Noctalia Greeter
    - configurar keyring
    - configurar NetworkManager / áudio / Bluetooth / Docker
    - configurar UFW
    - configurar SSH
    - executar setup.sh
    - habilitar greetd somente depois de tudo validado

  observações:
    - drivers de GPU não serão instalados
    - setup.sh fará backup dos arquivos KEEP antes de remover configs
    - UFW será resetado
    - Docker receberá integração UFW quando ufw-docker estiver disponível
    - instalação AUR é unattended (--skipreview)

EOF

read -rp "ENTER para começar unattended (Ctrl-C cancela)... " _

# ---------------------------------------------------------------------------
# Multilib
# ---------------------------------------------------------------------------

log "habilitando multilib em $PACMAN_CONF"

backup_once "$PACMAN_CONF"

sudo sed -i \
    's/^[[:space:]]*#\s*\[multilib\][[:space:]]*$/[multilib]/' \
    "$PACMAN_CONF"

sudo sed -i \
    '/^\[multilib\]/{n;s/^[[:space:]]*#\s*Include[[:space:]]*=/Include =/;}' \
    "$PACMAN_CONF"

if ! grep -A1 '^\[multilib\]' "$PACMAN_CONF" | grep -q '^Include ='; then
    warn "bloco [multilib] não parece estar habilitado."
fi

# ---------------------------------------------------------------------------
# Ferramentas necessárias antes do CachyOS
# ---------------------------------------------------------------------------

log "instalando ferramentas de bootstrap do Arch"

sudo pacman -Syu --needed --noconfirm \
    base-devel \
    curl \
    pciutils \
    ca-certificates \
    git

# ---------------------------------------------------------------------------
# Detecção da arquitetura da CPU
# ---------------------------------------------------------------------------

CPU_MARCH="$(
    gcc -march=native -Q --help=target 2>/dev/null |
        awk '$1 == "-march=" { print $2; exit }'
)"

ISA_REPO="v3"
ISA_PREVIEW="x86-64-v3"

case "$CPU_MARCH" in
    znver4|znver5)
        ISA_REPO="znver4"
        ISA_PREVIEW="$CPU_MARCH"
        ;;
    *)
        if /lib/ld-linux-x86-64.so.2 --help 2>/dev/null |
            grep -q 'x86-64-v4 (supported, searched)'; then
            ISA_REPO="v4"
            ISA_PREVIEW="x86-64-v4"
        elif /lib/ld-linux-x86-64.so.2 --help 2>/dev/null |
            grep -q 'x86-64-v3 (supported, searched)'; then
            ISA_REPO="v3"
            ISA_PREVIEW="x86-64-v3"
        else
            die "CPU sem suporte detectado para x86-64-v3; abortando para evitar repositório incompatível."
        fi
        ;;
esac

GPU_PREVIEW="$(
    lspci 2>/dev/null |
        grep -iE 'vga|3d|display' |
        head -n1 ||
        true
)"

[[ -n "$GPU_PREVIEW" ]] || GPU_PREVIEW="GPU não detectada"

log "CPU ISA detectada: $ISA_PREVIEW"
log "GPU detectada: $GPU_PREVIEW"

# ---------------------------------------------------------------------------
# CachyOS
# ---------------------------------------------------------------------------

if grep -qE '^\[cachyos' "$PACMAN_CONF"; then
    log "repositórios CachyOS já presentes."
else
    log "configurando repositórios CachyOS ($ISA_REPO)"

    MIRROR="https://mirror.cachyos.org/repo/x86_64/cachyos"
    LISTING="$(curl -fsSL "$MIRROR/" 2>/dev/null || true)"

    [[ -n "$LISTING" ]] ||
        die "não foi possível obter o diretório de pacotes CachyOS."

    latest_pkg() {
        local regex="$1"
        echo "$LISTING" |
            grep -oE "$regex" |
            sort -V |
            tail -n1
    }

    KEYRING_PKG="$(
        latest_pkg 'cachyos-keyring-[0-9][^"<> ]*\.pkg\.tar\.zst'
    )"

    MIRRORLIST_PKG="$(
        latest_pkg 'cachyos-mirrorlist-[0-9][^"<> ]*\.pkg\.tar\.zst'
    )"

    V3_PKG="$(
        latest_pkg 'cachyos-v3-mirrorlist-[0-9][^"<> ]*\.pkg\.tar\.zst'
    )"

    V4_PKG="$(
        latest_pkg 'cachyos-v4-mirrorlist-[0-9][^"<> ]*\.pkg\.tar\.zst'
    )"

    PACMAN_PKG="$(
        latest_pkg 'pacman-[0-9][^"<> ]*-x86_64\.pkg\.tar\.zst'
    )"

    [[ -n "$KEYRING_PKG" ]] ||
        die "cachyos-keyring não encontrado no mirror."

    [[ -n "$MIRRORLIST_PKG" ]] ||
        die "cachyos-mirrorlist não encontrado no mirror."

    [[ -n "$V3_PKG" ]] ||
        die "cachyos-v3-mirrorlist não encontrado no mirror."

    [[ -n "$V4_PKG" ]] ||
        die "cachyos-v4-mirrorlist não encontrado no mirror."

    [[ -n "$PACMAN_PKG" ]] ||
        die "pacman do CachyOS não encontrado no mirror."

    if ! sudo timeout 60 pacman-key \
        --recv-keys F3B607488DB35A47 \
        --keyserver keyserver.ubuntu.com; then

        sudo timeout 60 pacman-key \
            --recv-keys F3B607488DB35A47 \
            --keyserver keys.openpgp.org ||
            die "falha ao receber a chave CachyOS."
    fi

    sudo pacman-key --lsign-key F3B607488DB35A47

    log "instalando keyring, mirrorlists e pacman do CachyOS"

    sudo pacman -U --noconfirm --needed \
        "$MIRROR/$KEYRING_PKG" \
        "$MIRROR/$MIRRORLIST_PKG" \
        "$MIRROR/$V3_PKG" \
        "$MIRROR/$V4_PKG" \
        "$MIRROR/$PACMAN_PKG"

    REPO_FRAGMENT="$(mktemp)"

    case "$ISA_REPO" in
        v4)
            cat > "$REPO_FRAGMENT" <<'EOF'
[cachyos-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-core-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-extra-v4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist
EOF
            ;;

        znver4)
            cat > "$REPO_FRAGMENT" <<'EOF'
[cachyos-znver4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-core-znver4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos-extra-znver4]
Include = /etc/pacman.d/cachyos-v4-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist
EOF
            ;;

        v3)
            cat > "$REPO_FRAGMENT" <<'EOF'
[cachyos-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-core-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos-extra-v3]
Include = /etc/pacman.d/cachyos-v3-mirrorlist

[cachyos]
Include = /etc/pacman.d/cachyos-mirrorlist
EOF
            ;;

        *)
            rm -f "$REPO_FRAGMENT"
            die "ISA de repositório desconhecida: $ISA_REPO"
            ;;
    esac

    PACMAN_NEW="$(mktemp)"

    awk -v fragment="$REPO_FRAGMENT" '
        BEGIN {
            while ((getline line < fragment) > 0)
                block = block line ORS
            close(fragment)
        }

        $0 == "[core]" && !inserted {
            printf "%s\n", block
            inserted = 1
        }

        { print }
    ' "$PACMAN_CONF" > "$PACMAN_NEW"

    if ! grep -qE '^\[cachyos' "$PACMAN_NEW"; then
        rm -f "$REPO_FRAGMENT" "$PACMAN_NEW"
        die "não foi possível inserir os repositórios CachyOS antes dos repositórios Arch."
    fi

    sudo install -m 644 "$PACMAN_NEW" "$PACMAN_CONF"

    rm -f "$REPO_FRAGMENT" "$PACMAN_NEW"

    log "repositórios CachyOS adicionados antes dos repositórios Arch."
fi

# ---------------------------------------------------------------------------
# Atualização completa
# ---------------------------------------------------------------------------

log "sincronizando e atualizando o sistema"

sudo pacman -Syu --noconfirm

# ---------------------------------------------------------------------------
# Kernel headers
# ---------------------------------------------------------------------------

KERN_REL="$(uname -r)"
KERN_HEADERS="linux-headers"

case "$KERN_REL" in
    *cachyos*)
        KERN_HEADERS="linux-cachyos-headers"
        ;;
    *lts*)
        KERN_HEADERS="linux-lts-headers"
        ;;
    *zen*)
        KERN_HEADERS="linux-zen-headers"
        ;;
esac

log "kernel atual: $KERN_REL"
log "headers selecionados: $KERN_HEADERS"

# ---------------------------------------------------------------------------
# Pacotes
# ---------------------------------------------------------------------------

REQUIRED_PKGS=(
    wpa_supplicant
    networkmanager
    ufw
    ufw-extras
    openssh
    reflector
    nano
    vim
    git
    stow
    wget
    htop
    which
    xdg-utils
    curl
    pciutils

    pipewire
    pipewire-pulse
    pipewire-alsa
    pipewire-jack
    wireplumber
    pavucontrol
    playerctl

    libsecret
    gnome-keyring
    polkit-gnome
    polkit

    ananicy-cpp
    cachyos-ananicy-rules

    bluez
    bluez-utils
    bluez-hid2hci
    bluez-libs
    bluez-obex

    avahi
    cups

    systemd-timesyncd
    systemd-resolved

    python
    python-pip
    rust
    go
    tailscale

    jdk-openjdk
    nodejs
    npm
    pnpm

    docker
    docker-buildx
    docker-compose

    niri
    greetd
    noctalia

    unzip
    unrar
    snapper

    base-devel
    "$KERN_HEADERS"

    fish
    eza
    bat
    expac
    jq
    libnotify

    cachyos-rate-mirrors

    xdg-desktop-portal
    xdg-desktop-portal-gtk
    accountsservice

    power-profiles-daemon

    gamemode
    lib32-gamemode
    lib32-vulkan-icd-loader
    lib32-mangohud
    vulkan-icd-loader
    vulkan-tools

    7zip

    noto-fonts
    ttf-jetbrains-mono-nerd
)

OPTIONAL_PKGS=(
    btop
    fastfetch
    kitty
    mpv
    firefox
    sbctl
    steam
    discord
    spotify-launcher
    gimp
    protonplus
    faugus-launcher
    moonlight-qt
    sunshine
    qview
    btrfs-assistant
    opentabletdriver
    openrgb
    opencode
    gamescope
    goverlay
    mangohud
    limine-snapper-sync
    zed
    libreoffice-fresh
    qbittorrent
    yazi

    wine
    wine-mono
    wine-gecko
    winetricks
    umu-launcher
    protontricks
)

log "instalando pacotes obrigatórios (${#REQUIRED_PKGS[@]})"

sudo pacman -S --needed --noconfirm "${REQUIRED_PKGS[@]}" ||
    die "falha ao instalar um ou mais pacotes obrigatórios."

log "instalando pacotes opcionais (${#OPTIONAL_PKGS[@]})"

for pkg in "${OPTIONAL_PKGS[@]}"; do
    if sudo pacman -S --needed --noconfirm "$pkg"; then
        :
    else
        warn "pacote opcional indisponível/falhou: $pkg"
    fi
done

# ---------------------------------------------------------------------------
# paru
# ---------------------------------------------------------------------------

if command -v paru >/dev/null 2>&1; then
    log "paru já instalado: $(paru --version | head -n1)"
else
    log "instalando paru"

    if ! sudo pacman -S --needed --noconfirm paru; then
        warn "paru não está disponível nos repositórios; compilando paru-bin do AUR."

        TMP_PARU="$(mktemp -d)"

        git clone --depth 1 \
            https://aur.archlinux.org/paru-bin.git \
            "$TMP_PARU/paru-bin"

        if (
            cd "$TMP_PARU/paru-bin"
            makepkg -si --noconfirm --needed
        ); then
            rm -rf "$TMP_PARU"
        else
            rm -rf "$TMP_PARU"
            die "falha ao compilar paru-bin."
        fi
    fi
fi

command -v paru >/dev/null 2>&1 ||
    die "paru ainda não está disponível após a instalação."

# ---------------------------------------------------------------------------
# AUR
# ---------------------------------------------------------------------------

AUR_REQUIRED_PKGS=(
    noctalia-greeter
)

AUR_OPTIONAL_PKGS=(
    arch-update
    bpftune-git
    ufw-docker
    eden-bin
    xdg-desktop-portal-termfilechooser-hunkyburrito-git
    fish-done
)

export PARU_SKIP_REVIEW=1

log "instalando AUR obrigatório"

if ! paru -S --needed --noconfirm --skipreview --cleanafter \
    "${AUR_REQUIRED_PKGS[@]}"; then
    die "falha ao instalar AUR obrigatório."
fi

log "instalando AUR opcional"

for pkg in "${AUR_OPTIONAL_PKGS[@]}"; do
    if paru -S --needed --noconfirm --skipreview --cleanafter "$pkg"; then
        :
    else
        warn "AUR opcional falhou: $pkg"
    fi
done

# ---------------------------------------------------------------------------
# Validação de binários essenciais
# ---------------------------------------------------------------------------

for cmd in \
    niri \
    noctalia \
    noctalia-greeter-session \
    stow \
    fish \
    systemctl \
    ufw \
    sshd \
    paru
do
    command -v "$cmd" >/dev/null 2>&1 ||
        die "binário essencial não encontrado: $cmd"
done

# ---------------------------------------------------------------------------
# Display manager
# ---------------------------------------------------------------------------

log "configurando greetd como display manager"

for dm in sddm gdm lightdm ly lxdm; do
    if systemctl is-enabled "$dm.service" >/dev/null 2>&1; then
        warn "desabilitando $dm"

        sudo systemctl \
            --no-ask-password \
            --no-pager \
            disable "$dm.service" --now \
            2>/dev/null || true
    fi
done

if sudo getent group video >/dev/null 2>&1; then
    sudo usermod -aG video greeter 2>/dev/null || true
fi

if sudo getent group input >/dev/null 2>&1; then
    sudo usermod -aG input greeter 2>/dev/null || true
fi

SESSION_BIN="$(command -v noctalia-greeter-session)"

log "noctalia-greeter-session: $SESSION_BIN"

sudo mkdir -p "$(dirname "$GREETD_CONF")"

backup_once "$GREETD_CONF"

sudo tee "$GREETD_CONF" >/dev/null <<EOF
[terminal]
vt = 1

[default_session]
command = "$SESSION_BIN -- --session niri --user $TARGET_USER"
user = "greeter"
EOF

# ---------------------------------------------------------------------------
# Noctalia Greeter
# ---------------------------------------------------------------------------

log "configurando $GREETER_TOML"

sudo mkdir -p "$GREETER_DIR"

backup_once "$GREETER_TOML"

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

# ---------------------------------------------------------------------------
# PAM / GNOME Keyring
# ---------------------------------------------------------------------------

log "conferindo PAM do greetd para gnome-keyring"

if [[ -f /etc/pam.d/greetd ]]; then
    if ! grep -q 'pam_gnome_keyring' /etc/pam.d/greetd; then
        backup_once /etc/pam.d/greetd

        echo "-auth       optional      pam_gnome_keyring.so" |
            sudo tee -a /etc/pam.d/greetd >/dev/null

        echo "-session    optional      pam_gnome_keyring.so auto_start" |
            sudo tee -a /etc/pam.d/greetd >/dev/null
    fi
else
    warn "/etc/pam.d/greetd ainda não existe."
fi

sudo loginctl enable-linger "$TARGET_USER" 2>/dev/null || true

sudo -u "$TARGET_USER" \
    systemctl --user \
    --no-ask-password \
    --no-pager \
    enable gnome-keyring-daemon.socket \
    2>/dev/null || true

# ---------------------------------------------------------------------------
# Serviços do sistema
# ---------------------------------------------------------------------------

SYS_SERVICES=(
    NetworkManager
    ufw
    sshd
    bluetooth
    ananicy-cpp
    bpftune
    tailscaled
    docker
    docker.socket
    systemd-timesyncd
    systemd-resolved
    avahi-daemon
    cups
    cups.socket
)

SYS_TIMERS=(
    cachyos-rate-mirrors.timer
    snapper-timeline.timer
    snapper-cleanup.timer
    fstrim.timer
)

log "habilitando serviços de sistema"

for service in "${SYS_SERVICES[@]}"; do
    if systemctl list-unit-files "$service.service" >/dev/null 2>&1 &&
       systemctl cat "$service.service" >/dev/null 2>&1; then

        sudo systemctl \
            --no-ask-password \
            --no-pager \
            enable --now "$service" \
            2>/dev/null ||
            warn "falha ao habilitar $service"
    fi
done

# ---------------------------------------------------------------------------
# Power profiles
# ---------------------------------------------------------------------------

if systemctl is-enabled tlp.service >/dev/null 2>&1 ||
   systemctl is-enabled auto-cpufreq.service >/dev/null 2>&1; then

    warn "tlp/auto-cpufreq detectado — não habilitando power-profiles-daemon."
else
    sudo systemctl \
        --no-ask-password \
        --no-pager \
        enable --now power-profiles-daemon \
        2>/dev/null ||
        warn "falha ao habilitar power-profiles-daemon"
fi

# ---------------------------------------------------------------------------
# Timers
# ---------------------------------------------------------------------------

for timer in "${SYS_TIMERS[@]}"; do
    if systemctl list-unit-files "$timer" >/dev/null 2>&1 &&
       systemctl cat "$timer" >/dev/null 2>&1; then

        sudo systemctl \
            --no-ask-password \
            --no-pager \
            enable --now "$timer" \
            2>/dev/null ||
            warn "falha ao habilitar timer $timer"
    fi
done

if systemctl list-unit-files reflector.timer 2>/dev/null |
    grep -q '^reflector\.timer'; then

    sudo systemctl \
        --no-ask-password \
        --no-pager \
        enable --now reflector.timer \
        2>/dev/null || true
fi

if systemctl list-unit-files 2>/dev/null |
    grep -q '^limine-snapper-sync\.service'; then

    sudo systemctl \
        --no-ask-password \
        --no-pager \
        enable --now limine-snapper-sync.service \
        2>/dev/null ||
        warn "limine-snapper-sync indisponível."
fi

if systemctl list-unit-files 2>/dev/null |
    grep -q '^limine-snapper-watcher\.service'; then

    sudo systemctl \
        --no-ask-password \
        --no-pager \
        enable --now limine-snapper-watcher.service \
        2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Snapper somente se root for Btrfs
# ---------------------------------------------------------------------------

ROOT_FS="$(findmnt -no FSTYPE / 2>/dev/null || true)"

if [[ "$ROOT_FS" == "btrfs" ]]; then
    log "root é Btrfs — configurando Snapper"

    sudo snapper -c root list 2>/dev/null ||
        sudo snapper -c root create-config / 2>/dev/null ||
        warn "não foi possível configurar Snapper."
else
    log "root não é Btrfs ($ROOT_FS) — pulando configuração Snapper."
fi

# ---------------------------------------------------------------------------
# Docker
# ---------------------------------------------------------------------------

sudo usermod -aG docker "$TARGET_USER" 2>/dev/null || true

# ---------------------------------------------------------------------------
# Serviços de usuário
# ---------------------------------------------------------------------------

log "habilitando serviços de usuário"

sudo -u "$TARGET_USER" \
    systemctl --user \
    --no-ask-password \
    --no-pager \
    enable \
    pipewire.socket \
    pipewire-pulse.socket \
    wireplumber.service \
    playerctld.service \
    opentabletdriver.service \
    2>/dev/null ||
    warn "alguns user-services não puderam ser habilitados."

sudo -u "$TARGET_USER" \
    systemctl --user \
    --no-ask-password \
    --no-pager \
    start \
    pipewire-pulse.socket \
    wireplumber.service \
    playerctld.service \
    2>/dev/null || true

sudo -u "$TARGET_USER" \
    systemctl --user \
    --no-ask-password \
    --no-pager \
    enable app-dev.lizardbyte.app.Sunshine.service \
    2>/dev/null || true

if sudo -u "$TARGET_USER" \
    systemctl --user list-unit-files 2>/dev/null |
    grep -q 'arch-update.timer'; then

    sudo -u "$TARGET_USER" \
        systemctl --user \
        --no-ask-password \
        --no-pager \
        enable --now arch-update.timer \
        2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# UFW
# ---------------------------------------------------------------------------

log "configurando UFW"

backup_once /etc/ufw/user.rules
backup_once /etc/ufw/user6.rules
backup_once /etc/ufw/after.rules
backup_once /etc/ufw/after6.rules

sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh

# Sunshine
# HTTPS/UI: 47984, 47989-47990, 48010 TCP
# Streaming: 47998-48000 UDP
sudo ufw allow 47984:47990/tcp
sudo ufw allow 48010/tcp
sudo ufw allow 47998:48000/udp

sudo ufw --force enable

sudo systemctl \
    --no-ask-password \
    --no-pager \
    enable --now ufw

if command -v ufw-docker >/dev/null 2>&1; then
    log "configurando integração UFW + Docker"

    sudo ufw-docker install \
        --docker-subnets \
        2>/dev/null ||
        warn "ufw-docker falhou ao configurar as regras."
else
    warn "ufw-docker não instalado; Docker pode ignorar regras do UFW."
fi

if systemctl is-active docker.service >/dev/null 2>&1; then
    sudo systemctl \
        --no-ask-password \
        --no-pager \
        restart docker \
        2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# SSH
# ---------------------------------------------------------------------------

log "configurando sshd"

SSHD_CONF="/etc/ssh/sshd_config.d/10-hardened.conf"

backup_once /etc/ssh/sshd_config

sudo mkdir -p /etc/ssh/sshd_config.d

if sudo -u "$TARGET_USER" test \
    -f "$TARGET_HOME/.ssh/authorized_keys"; then

    sudo tee "$SSHD_CONF" >/dev/null <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
X11Forwarding no
EOF

    sudo sshd -t ||
        die "sshd -t falhou após escrever $SSHD_CONF."
else
    sudo tee "$SSHD_CONF" >/dev/null <<'EOF'
PermitRootLogin no
X11Forwarding no
EOF

    sudo sshd -t ||
        die "sshd -t falhou após escrever $SSHD_CONF."

    warn "nenhuma authorized_keys encontrada — login por senha permanece habilitado."
fi

sudo systemctl \
    --no-ask-password \
    --no-pager \
    enable --now sshd

# ---------------------------------------------------------------------------
# setup.sh
# ---------------------------------------------------------------------------

log "executando setup.sh"

bash "$DOTFILES/setup.sh"

# ---------------------------------------------------------------------------
# Validação pós-setup
# ---------------------------------------------------------------------------

log "validando instalação"

[[ -L "$TARGET_HOME/.config/niri" || -d "$TARGET_HOME/.config/niri" ]] ||
    die "Niri não foi configurado pelo setup.sh."

[[ -L "$TARGET_HOME/.config/noctalia" || -d "$TARGET_HOME/.config/noctalia" ]] ||
    die "Noctalia não foi configurado pelo setup.sh."

[[ -x "$TARGET_HOME/.config/xdg-desktop-portal-termfilechooser/yazi-wrapper.sh" ]] ||
    warn "yazi-wrapper.sh não está executável."

pacman -Q noctalia-greeter >/dev/null 2>&1 ||
    die "noctalia-greeter não está instalado."

pacman -Q fish-done >/dev/null 2>&1 ||
    warn "fish-done ausente."

# ---------------------------------------------------------------------------
# Greetd — somente agora
# ---------------------------------------------------------------------------

log "habilitando greetd somente após a instalação ter sido validada"

sudo systemctl \
    --no-ask-password \
    --no-pager \
    enable greetd.service

# ---------------------------------------------------------------------------
# Final
# ---------------------------------------------------------------------------

cat <<EOF

Concluído.

Próximos passos manuais:

  1. Abra o Noctalia e faça:
       Settings → Security → Noctalia Greeter → Sync Now

  2. Depois:
       sudo systemctl restart greetd

  3. Secure Boot:
       sbctl status

     O gerenciamento/enrollment permanece manual.

  4. Tailscale:
       sudo tailscale up

  5. Drivers de GPU:
       não foram instalados por este script.

  6. Recomendado:
       sudo reboot

  7. Depois do login:
       exec fish

Verificação rápida:

  pacman -Q paru niri noctalia noctalia-greeter
  systemctl is-enabled greetd ufw sshd bluetooth docker tailscaled
  systemctl --user is-enabled playerctld wireplumber
  cat "$GREETD_CONF"
  sudo ufw status verbose
  docker info

CPU ISA:
  $ISA_PREVIEW

GPU:
  $GPU_PREVIEW

Root filesystem:
  $ROOT_FS

EOF
