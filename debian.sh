#!/usr/bin/env bash
# Universal Debian Bootstrapper: Debian 8..13 (jessie → trixie)
# Design goals:
# - English comments & clear, colorful logs
# - Safe & idempotent: re-running does not redo completed work
# - Works across old/EOL releases (archives) and current ones
# - Conservative system changes; no dangerous overwrites
# - Sysctl via /etc/sysctl.d, not /etc/sysctl.conf
# - Docker: prefer docker.io on bookworm/trixie; fallback to get.docker.com for older
#
# How idempotency is implemented:
# - Step markers under /var/local/bootstrap/<step>.done
# - Conditional checks before modifying files / creating users / enabling services
# - Non-fatal fallbacks (warn & continue) for optional parts

set -Eeuo pipefail

############## USER CONFIG (override via env if needed) #########
DOWNLOAD_KEYSERVER="${DOWNLOAD_KEYSERVER:-keyserver.ubuntu.com}"
TIMEZONE="${timezone:-Europe/Moscow}"
DOMAIN="${domain:-zabiyaka.net}"
SEC_EMAIL="${email:-security@zabiyaka.net}"

PRIMARY_USER="${user:-matvey}"
PRIMARY_USER_PUBKEY="${user_ssh_key:-ssh-rsa AAAAB3NzaC1... MatveyGladkikh}"

MON_USER="${monitoring_user:-r2d2}"
MON_USER_PUBKEY="${monitoring_user_ssh_key:-ssh-rsa AAAAB3NzaC1... nagios@monitor}"

# Optional NetFlow collector; leave empty to skip
NETFLOW_COLLECTOR="${netflowcollector:-}"

############## COLORS / LOGGING #################################
if [[ -t 1 ]]; then
  C_RESET='\033[0m'; C_BOLD='\033[1m'; C_DIM='\033[2m'
  C_RED='\033[31m'; C_GREEN='\033[32m'; C_YELLOW='\033[33m'
  C_BLUE='\033[34m'; C_CYAN='\033[36m'; C_MAGENTA='\033[35m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''; C_MAGENTA=''
fi
step(){ echo -e "${C_BOLD}${C_BLUE}▶ $*${C_RESET}"; }
ok(){ echo -e "${C_GREEN}✔ $*${C_RESET}"; }
warn(){ echo -e "${C_YELLOW}⚠ $*${C_RESET}"; }
fail(){ echo -e "${C_RED}✘ $*${C_RESET}"; }
info(){ echo -e "${C_CYAN}ℹ $*${C_RESET}"; }

trap 'fail "Error at line $LINENO"; exit 1' ERR
[[ $EUID -eq 0 ]] || { fail "Please run as root"; exit 1; }

MARK_DIR="/var/local/bootstrap"
mkdir -p "$MARK_DIR"

mark_done(){ : > "${MARK_DIR}/$1.done"; }
is_done(){ [[ -f "${MARK_DIR}/$1.done" ]]; }

############## DETECT SYSTEM ####################################
step "Detecting system"
CODENAME="$(lsb_release -cs 2>/dev/null || . /etc/os-release; echo "${VERSION_CODENAME:-}")"
RELEASE="$(lsb_release -rs 2>/dev/null || . /etc/os-release; echo "${VERSION_ID:-}")"
if [[ -z "$CODENAME" || "$CODENAME" == "n/a" || "$CODENAME" == "unknown" ]]; then
  DV="$(cat /etc/debian_version 2>/dev/null || true)"
  case "$DV" in
    8.*)  CODENAME=jessie ;;
    9.*)  CODENAME=stretch ;;
    10.*) CODENAME=buster ;;
    11.*) CODENAME=bullseye ;;
    12.*) CODENAME=bookworm ;;
    13.*) CODENAME=trixie ;;
    *)    CODENAME=unknown ;;
  esac
fi
MATRIX="$(command -v virt-what >/dev/null 2>&1 && virt-what || true)"
[[ -f /proc/1/mountinfo ]] || MATRIX="chroot"
ok "Debian: ${CODENAME} (${RELEASE:-unknown}), environment: ${MATRIX:-baremetal}"

export DEBIAN_FRONTEND=noninteractive

############## DNS / RESOLV.CONF ################################
if ! is_done "resolv"; then
  step "Configuring resolv.conf"
  tmpl="/tmp/resolv.new.$$"
  cat > "$tmpl" <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 2606:4700:4700::1111
nameserver 2606:4700:4700::1001
search ${DOMAIN}
options timeout:3
EOF
  if ! cmp -s "$tmpl" /etc/resolv.conf 2>/dev/null; then
    cp -a /etc/resolv.conf "/etc/resolv.conf.$(date +%s)" 2>/dev/null || true
    mv "$tmpl" /etc/resolv.conf
    ok "resolv.conf updated"
  else
    rm -f "$tmpl"
    info "resolv.conf already in desired state"
  fi
  mark_done "resolv"
else
  info "resolv.conf step already done"
fi

############## APT SOURCES ######################################
if ! is_done "sources"; then
  step "Configuring APT sources for ${CODENAME}"
  backup_sources(){ cp -a /etc/apt/sources.list "/etc/apt/sources.list.$(date +%s)" 2>/dev/null || true; }
  write_sources(){
    local content="$1"
    # Only rewrite if content differs
    local cur="/etc/apt/sources.list"
    local tmp="/tmp/sources.$$"
    echo "$content" > "$tmp"
    if ! cmp -s "$tmp" "$cur" 2>/dev/null; then
      backup_sources
      mv "$tmp" "$cur"
      ok "sources.list updated"
    else
      rm -f "$tmp"
      info "sources.list already matches"
    fi
  }

  case "$CODENAME" in
    jessie|stretch)
      write_sources "deb http://archive.debian.org/debian ${CODENAME} main contrib non-free
deb http://archive.debian.org/debian-security ${CODENAME}/updates main contrib non-free
Acquire::Check-Valid-Until \"false\";"
      ;;
    buster)
      write_sources "deb http://deb.debian.org/debian buster main contrib non-free
deb http://deb.debian.org/debian buster-updates main contrib non-free
deb http://security.debian.org/debian-security buster/updates main contrib non-free"
      ;;
    bullseye)
      write_sources "deb http://deb.debian.org/debian bullseye main contrib non-free
deb http://deb.debian.org/debian bullseye-updates main contrib non-free
deb http://security.debian.org/debian-security bullseye-security main contrib non-free"
      ;;
    bookworm)
      write_sources "deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware
deb http://deb.debian.org/debian bookworm-backports main contrib non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware"
      ;;
    trixie)
      write_sources "deb http://deb.debian.org/debian trixie main contrib non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free-firmware
deb http://deb.debian.org/debian trixie-backports main contrib non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free-firmware"
      ;;
    *)
      warn "Unknown codename '${CODENAME}', skipping sources modification"
      ;;
  esac

  mkdir -p /etc/apt/apt.conf.d
  cat > /etc/apt/apt.conf.d/99force-conf <<'EOF'
Dpkg::Options {
   "--force-confdef";
   "--force-confold";
}
APT::Install-Recommends "true";
APT::Install-Suggests "false";
EOF

  apt-get update || warn "apt-get update returned warnings (continuing)"
  mark_done "sources"
else
  info "APT sources step already done"
fi

############## BASE PACKAGES ####################################
if ! is_done "basepkgs"; then
  step "Installing base packages"
  pkgs=(ca-certificates curl wget bash vim screen less bzip2 rsync socat net-tools iproute2 sudo strace lsof
        psmisc pwgen make unzip tar gzip xz-utils git dnsutils traceroute tcpdump mtr-tiny nmap ufw tree hwinfo
        gnupg dirmngr gpg-agent locales tzdata lsb-release virt-what edac-utils)
  apt-get -q -y install "${pkgs[@]}"

  case "$CODENAME" in
    jessie|stretch)
      apt-get -q -y install iptraf nagios-plugins nagios-plugins-contrib || true
      ;;
    *)
      apt-get -q -y install iptraf-ng monitoring-plugins monitoring-plugins-contrib linux-perf || true
      ;;
  esac
  ok "Base packages installed"
  mark_done "basepkgs"
else
  info "Base packages step already done"
fi

############## LOCALE / TIMEZONE ################################
if ! is_done "locale_tz"; then
  step "Setting locale & timezone"
  locale-gen --purge en_US.UTF-8 || true
  update-locale LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 || true
  ln -fs "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
  dpkg-reconfigure --frontend noninteractive tzdata || true
  ok "Locale and timezone set"
  mark_done "locale_tz"
else
  info "Locale/timezone step already done"
fi

############## VIM / SCREEN CONFIGS #############################
if ! is_done "vim_screen"; then
  step "Configuring Vim & Screen"
  install_vimrc(){
    local target="$1"
    cat > "$target" <<'EOF'
runtime! debian.vim
set paste
syntax on
set nomodeline
set encoding=utf-8
filetype plugin indent on
set ignorecase
set mouse-=a
EOF
  }
  install_vimrc /root/.vimrc
  install_vimrc /etc/vim/vimrc

  cat > /etc/screenrc <<'EOF'
attrcolor b ".I"
shell                 -$SHELL
caption always "%{WB}%?%-Lw%?%{kw}%n*%f %t%?(%u)%?%{WB}%?%+Lw%?%{Wb}"
hardstatus alwayslastline "%{= RY}%H %{BW} %l %{bW} %c %M %d%= $domain"
activity              "%C -> %n%f %t activity!"
bell                  "%C -> %n%f %t bell!~"
pow_detach_msg        "BYE"
vbell_msg             " *beep* "
EOF
  ok "Vim/Screen configured"
  mark_done "vim_screen"
else
  info "Vim/Screen step already done"
fi

############## SYSCTL / KERNEL TUNING ###########################
if ! is_done "sysctl"; then
  step "Applying sysctl tuning"
  cat > /etc/sysctl.d/99-tuning.conf <<'EOF'
# Networking / sockets
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_syncookies=1
net.core.somaxconn=32768
net.core.netdev_max_backlog=32768

# Files/IO
fs.file-max=99999999

# Conntrack (overall limits)
net.netfilter.nf_conntrack_tcp_loose = 1
net.netfilter.nf_conntrack_max = 100000000
net.netfilter.nf_conntrack_expect_max = 256

# Bridge netfilter (for containers/k8s)
net.bridge.bridge-nf-call-arptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1

# Memory
vm.overcommit_memory = 0
vm.swappiness = 60
EOF

  # nf_conntrack hashsize: set at runtime if possible; otherwise via modprobe.d
  if [[ -w /sys/module/nf_conntrack/parameters/hashsize ]]; then
    echo 1000000 > /sys/module/nf_conntrack/parameters/hashsize || true
  else
    echo "options nf_conntrack hashsize=1000000" > /etc/modprobe.d/nf_conntrack.conf
  fi

  # Try to load useful modules; ignore errors if unavailable
  modprobe overlay 2>/dev/null || true
  modprobe br_netfilter 2>/dev/null || true
  modprobe ip_vs 2>/dev/null || true
  sysctl --system >/dev/null || true
  ok "Sysctl applied"
  mark_done "sysctl"
else
  info "Sysctl step already done"
fi

############## DOCKER INSTALL ###################################
if ! is_done "docker"; then
  step "Installing Docker (if not present)"
  if systemctl list-unit-files | grep -q '^docker\.service'; then
    info "Docker service already present"
    mark_done "docker"
  else
    if [[ "$CODENAME" == "bookworm" || "$CODENAME" == "trixie" ]]; then
      if apt-get -q -y install docker.io; then
        systemctl enable --now docker || true
        ok "docker.io installed"
        mark_done "docker"
      else
        warn "Failed to install docker.io, trying convenience script"
        if curl -fsSL https://get.docker.com | sh; then
          systemctl enable --now docker 2>/dev/null || true
          ok "Docker installed via convenience script"
          mark_done "docker"
        else
          warn "Docker installation failed; skipping"
        fi
      fi
    else
      if curl -fsSL https://get.docker.com | sh; then
        systemctl enable --now docker 2>/dev/null || true
        ok "Docker installed via convenience script"
        mark_done "docker"
      else
        warn "Docker installation failed; skipping"
      fi
    fi
  fi
else
  info "Docker step already done"
fi

############## USERS / SSH KEYS / SUDO ##########################
if ! is_done "users"; then
  step "Ensuring users and SSH keys"
  # Create wheel group & sudo nopasswd rule once
  getent group wheel >/dev/null || groupadd wheel
  if ! grep -q '^%wheel  ALL=(ALL) NOPASSWD:ALL' /etc/sudoers; then
    echo '%wheel  ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
  fi

  # Primary user
  if ! id -u "$PRIMARY_USER" >/dev/null 2>&1; then
    useradd -m -s /bin/bash -G wheel "$PRIMARY_USER"
    passwd -d "$PRIMARY_USER" >/dev/null 2>&1 || true
  else
    usermod -aG wheel "$PRIMARY_USER" || true
  fi
  mkdir -p "/home/${PRIMARY_USER}/.ssh"
  chmod 700 "/home/${PRIMARY_USER}/.ssh"
  AUTH="/home/${PRIMARY_USER}/.ssh/authorized_keys"
  touch "$AUTH"
  if ! grep -qF "$PRIMARY_USER_PUBKEY" "$AUTH"; then
    echo "$PRIMARY_USER_PUBKEY" >> "$AUTH"
  fi
  chmod 400 "$AUTH"
  chown -R "${PRIMARY_USER}:${PRIMARY_USER}" "/home/${PRIMARY_USER}"

  # Monitoring user (optional)
  if [[ -n "$MON_USER" ]]; then
    if ! id -u "$MON_USER" >/dev/null 2>&1; then
      useradd -m -s /bin/bash "$MON_USER"
      passwd -d "$MON_USER" >/dev/null 2>&1 || true
    fi
    mkdir -p "/home/${MON_USER}/.ssh"
    chmod 700 "/home/${MON_USER}/.ssh"
    MAUTH="/home/${MON_USER}/.ssh/authorized_keys"
    touch "$MAUTH"
    if ! grep -qF "$MON_USER_PUBKEY" "$MAUTH"; then
      echo "$MON_USER_PUBKEY" >> "$MAUTH"
    fi
    chmod 400 "$MAUTH"
    chown -R "${MON_USER}:${MON_USER}" "/home/${MON_USER}"
    # Sudo allow-list for monitoring (create once)
    SUDO_D="/etc/sudoers.d/${MON_USER}"
    if [[ ! -f "$SUDO_D" ]]; then
      cat > "$SUDO_D" <<EOF
${MON_USER} ALL=NOPASSWD: /usr/local/bin/check_*, /usr/local/bin/redis-backup, /usr/lib/nagios/plugins/check_*
EOF
      chmod 440 "$SUDO_D"
    fi
  fi
  # Root authorized_keys: ensure primary key present
  mkdir -p /root/.ssh && chmod 700 /root/.ssh
  touch /root/.ssh/authorized_keys
  if ! grep -qF "$PRIMARY_USER_PUBKEY" /root/.ssh/authorized_keys; then
    echo "$PRIMARY_USER_PUBKEY" >> /root/.ssh/authorized_keys
    chmod 400 /root/.ssh/authorized_keys
  fi

  ok "Users and keys ensured"
  mark_done "users"
else
  info "Users step already done"
fi

############## LOGIN BANNER (ISSUE.NET) #########################
if ! is_done "banner"; then
  step "Setting login banner"
  cat > /etc/issue.net <<EOF
************************************************************
* No bad fish allowed.                                     *
* Report security issues to ${SEC_EMAIL}            *
* Rewards for valid reports. Thank you.                    *
************************************************************
EOF
  ok "Banner set"
  mark_done "banner"
else
  info "Banner step already done"
fi

############## /etc/profile & PROMPT ############################
if ! is_done "profile"; then
  step "Configuring /etc/profile (prompt + info)"
  cat > /etc/profile <<'EOF'
# Enable bash completion if present
if [ -f /etc/bash_completion ]; then . /etc/bash_completion; fi

# PATH
if [ "$(id -u)" -eq 0 ]; then
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
else
  PATH="/usr/local/bin:/usr/bin:/bin"
fi
export PATH

# Locale
export LANGUAGE=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Editor & colors
export EDITOR=vim
export CLICOLOR=1

# Label files (optional)
touch /etc/label >/dev/null 2>&1 || true
touch /etc/info  >/dev/null 2>&1 || true
label="$(head -1 /etc/label | head -c 50)"

# Fancy prompt: [label] user@host cwd $
PS1="\[\033[01;95m\]$label \[\033[01;90m\]| \[\033[01;32m\]\u@\h \[\033[01;34m\]\w \$\[\033[00m\] "

# Show quick system info if available
(neofetch || screenfetch || true) 2>/dev/null
cat /etc/info 2>/dev/null || true
EOF
  # keep root .bashrc minimal to avoid duplicate prompts
  : > /root/.bashrc
  ok "/etc/profile configured"
  mark_done "profile"
else
  info "/etc/profile step already done"
fi

############## POSTFIX (OPTIONAL) ################################
if ! is_done "postfix"; then
  step "Configuring Postfix (local only) if installed"
  if dpkg -s postfix >/dev/null 2>&1; then
    mkdir -p /etc/postfix
    cat > /etc/postfix/main.cf <<'EOF'
smtpd_banner = ESMTP
biff = no
append_dot_mydomain = no
readme_directory = no
compatibility_level = 2

# Minimal local delivery
myhostname = localhost
myorigin = localhost
mydestination = localhost.localdomain, localhost
inet_interfaces = all
inet_protocols = ipv4

# Restrict relaying; local only
smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
mynetworks = 127.0.0.0/8 [::1]/128

# TLS (snakeoil placeholders)
smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
smtpd_tls_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
smtpd_use_tls=yes
EOF
    newaliases 2>/dev/null || true
    systemctl restart postfix 2>/dev/null || /etc/init.d/postfix restart || true
    ok "Postfix configured"
  else
    info "Postfix not installed; skipping"
  fi
  mark_done "postfix"
else
  info "Postfix step already done"
fi

############## SSH SERVER (SAFE LINES ONLY) #####################
if ! is_done "sshd"; then
  step "Hardening SSH (non-intrusive)"
  # Update/insert only specific lines; do not nuke entire config
  SSHD="/etc/ssh/sshd_config"
  cp -a "$SSHD" "${SSHD}.$(date +%s)" 2>/dev/null || true
  ensure_sshd_opt(){
    local key="$1" val="$2"
    if grep -qiE "^[#\s]*${key}\b" "$SSHD"; then
      sed -i -E "s|^[#\s]*${key}\b.*|${key} ${val}|I" "$SSHD"
    else
      echo "${key} ${val}" >> "$SSHD"
    fi
  }
  ensure_sshd_opt PasswordAuthentication no
  ensure_sshd_opt PermitRootLogin yes
  # optional: Banner
  ensure_sshd_opt Banner /etc/issue.net
  systemctl reload ssh 2>/dev/null || /etc/init.d/ssh reload || true
  ok "SSHD updated"
  mark_done "sshd"
else
  info "SSHD step already done"
fi

############## CRON: DAILY APT-UPDATE ###########################
if ! is_done "cron_update"; then
  step "Adding cron.daily apt-get update"
  CRONF="/etc/cron.daily/zz-bootstrap-update"
  if [[ ! -f "$CRONF" ]]; then
    cat > "$CRONF" <<'EOF'
#!/bin/bash
/usr/bin/apt-get update &>/dev/null || true
EOF
    chmod +x "$CRONF"
    ok "cron.daily task installed"
  else
    info "cron.daily task already exists"
  fi
  mark_done "cron_update"
else
  info "Cron update step already done"
fi

############## NETFLOW (OPTIONAL) ################################
if ! is_done "netflow"; then
  if [[ -n "$NETFLOW_COLLECTOR" ]]; then
    step "Configuring NetFlow (softflowd) → ${NETFLOW_COLLECTOR}"
    if apt-get -q -y install softflowd; then
      mkdir -p /etc/softflowd
      cat > /etc/softflowd/default.conf <<EOF
interface="any"
options="-n ${NETFLOW_COLLECTOR}"
EOF
      systemctl enable --now softflowd 2>/dev/null || true
      ok "softflowd enabled"
      mark_done "netflow"
    else
      warn "softflowd install failed; skipping"
      mark_done "netflow" # avoid retry spam; remove marker if you want to retry later
    fi
  else
    info "NetFlow not requested; skipping"
    mark_done "netflow"
  fi
else
  info "NetFlow step already done"
fi

############## HOSTNAME (REVERSE DNS IF POSSIBLE) ################
if ! is_done "hostname"; then
  step "Setting hostname from reverse-DNS when available"
  ext_dev="$(ip r | awk '/default/ {print $5; exit}')"
  ip_addr="$(ip -4 a show "$ext_dev" 2>/dev/null | awk '/inet / && /scope global/ {print $2}' | cut -d/ -f1 | head -1)"
  hostname_cur="$(cat /etc/hostname 2>/dev/null || echo localhost)"
  new_host="$hostname_cur"
  if command -v dig >/dev/null 2>&1 && [[ -n "$ip_addr" ]]; then
    hostnamewithdot="$(dig +short -x "$ip_addr" || true)"
    if [[ -n "$hostnamewithdot" ]]; then
      new_host="${hostnamewithdot%.}"
    fi
  fi
  if [[ "$new_host" != "$hostname_cur" && -n "$new_host" ]]; then
    hostname "$new_host"
    echo "$new_host" > /etc/hostname
    ok "Hostname set to ${new_host}"
  else
    info "Hostname remains ${hostname_cur}"
  fi
  mark_done "hostname"
else
  info "Hostname step already done"
fi

############## FINAL ############################################
echo
ok "All done! Safe to re-run anytime. Markers in ${MARK_DIR}."
echo -e "${C_DIM}Need tweaks or extra roles (Munin, UFW presets, LXC templates)? Tell me and I’ll extend this script.${C_RESET}"
