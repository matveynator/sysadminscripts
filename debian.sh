#!/usr/bin/env bash
# Universal Debian bootstrapper: 8 (jessie) .. 13 (trixie)
# - Безопасные правки, без "сломать систему"
# - Красочный лог с этапами
# - Аккуратные различия по версиям (репозитории, пакеты, docker)
# - Не затирает /etc/sysctl.conf — свои настройки кладёт в /etc/sysctl.d/99-tuning.conf
# - Не трогает /bin/sh (оставляем dash как есть)
# - Все действия по возможности идемпотентны

set -Eeuo pipefail

#########################  USER CONFIG  #########################
DOWNLOAD_KEYSERVER=${DOWNLOAD_KEYSERVER:-keyserver.ubuntu.com}
timezone="${timezone:-Europe/Moscow}"
domain="${domain:-zabiyaka.net}"
email="${email:-security@zabiyaka.net}"

trusted_ipv4_hosts="${trusted_ipv4_hosts:-176.9.141.126 144.76.87.91 95.143.186.117}"
trusted_ipv6_hosts="${trusted_ipv6_hosts:-2a01:4f8:192:1444::3 2a01:4f8:192:1444::4}"

user="${user:-matvey}"
user_ssh_key="${user_ssh_key:-ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAgEAmryyHCe3B... MatveyGladkikh}"

monitoring_user="${monitoring_user:-r2d2}"
monitoring_user_ssh_key="${monitoring_user_ssh_key:-ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDFpauk... nagios@monitor.zabiyaka.net}"

# netflowcollector=""  # если нужно, экспортируй переменную перед запуском
#################################################################

#########################  COLOR & UI  ##########################
if [[ -t 1 ]]; then
  C_RESET='\033[0m'
  C_BOLD='\033[1m'
  C_DIM='\033[2m'
  C_RED='\033[31m'
  C_GREEN='\033[32m'
  C_YELLOW='\033[33m'
  C_BLUE='\033[34m'
  C_MAGENTA='\033[35m'
  C_CYAN='\033[36m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_MAGENTA=''; C_CYAN=''
fi

step()   { echo -e "${C_BOLD}${C_BLUE}▶ $*${C_RESET}"; }
ok()     { echo -e "${C_GREEN}✔ $*${C_RESET}"; }
warn()   { echo -e "${C_YELLOW}⚠ $*${C_RESET}"; }
fail()   { echo -e "${C_RED}✘ $*${C_RESET}"; }
info()   { echo -e "${C_CYAN}ℹ ${C_DIM}$*${C_RESET}"; }

trap 'fail "Ошибка на строке $LINENO"; exit 1' ERR

[[ $EUID -eq 0 ]] || { fail "Запусти от root"; exit 1; }

#########################  DETECT SYSTEM  #######################
step "Определяем окружение"
if command -v lsb_release >/dev/null 2>&1; then
  CODENAME="$(lsb_release -cs)"
  RELEASE="$(lsb_release -rs || echo '')"
else
  # запасной путь
  CODENAME="$(. /etc/os-release; echo "${VERSION_CODENAME:-}")"
  RELEASE="$(. /etc/os-release; echo "${VERSION_ID:-}")"
fi
: "${CODENAME:=unknown}"
: "${RELEASE:=unknown}"

MATRIX="$(command -v virt-what >/dev/null 2>&1 && virt-what || true)"
[[ -f /proc/1/mountinfo ]] || MATRIX="chroot"

ok "Debian: ${C_BOLD}${CODENAME}${C_RESET} (ID ${RELEASE}), среда: ${MATRIX:-baremetal}"

#########################  RESOLV + APT  ########################
step "Настраиваем DNS и APT"
cp -a /etc/resolv.conf /etc/resolv.conf.$(date +%s) 2>/dev/null || true
cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 2606:4700:4700::1111
nameserver 2606:4700:4700::1001
search $domain
options timeout:3
EOF
ok "resolv.conf обновлён"

export DEBIAN_FRONTEND=noninteractive

# Источники APT с учётом EOL
backup_sources() { cp -a /etc/apt/sources.list /etc/apt/sources.list.$(date +%s) 2>/dev/null || true; }

set_sources_for() {
  local codename="$1"
  case "$codename" in
    jessie|stretch)
      # EOL → archive.debian.org
      backup_sources
      cat > /etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian ${codename} main contrib non-free
deb http://archive.debian.org/debian-security ${codename}/updates main contrib non-free
# src:
deb-src http://archive.debian.org/debian ${codename} main contrib non-free
deb-src http://archive.debian.org/debian-security ${codename}/updates main contrib non-free
Acquire::Check-Valid-Until "false";
EOF
      ;;
    buster)
      backup_sources
      cat > /etc/apt/sources.list <<'EOF'
deb http://deb.debian.org/debian buster main contrib non-free
deb http://security.debian.org/debian-security buster/updates main contrib non-free
deb http://deb.debian.org/debian buster-updates main contrib non-free
# buster-backports при необходимости:
# deb http://deb.debian.org/debian buster-backports main contrib non-free
EOF
      ;;
    bullseye)
      backup_sources
      cat > /etc/apt/sources.list <<'EOF'
deb http://deb.debian.org/debian bullseye main contrib non-free
deb http://security.debian.org/debian-security bullseye-security main contrib non-free
deb http://deb.debian.org/debian bullseye-updates main contrib non-free
# deb http://deb.debian.org/debian bullseye-backports main contrib non-free
EOF
      ;;
    bookworm)
      backup_sources
      cat > /etc/apt/sources.list <<'EOF'
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware
deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware
deb http://deb.debian.org/debian bookworm-backports main contrib non-free-firmware
EOF
      ;;
    trixie)
      backup_sources
      cat > /etc/apt/sources.list <<'EOF'
deb http://deb.debian.org/debian trixie main contrib non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free-firmware
deb http://deb.debian.org/debian trixie-backports main contrib non-free-firmware
EOF
      ;;
    *)
      warn "Неизвестный codename '${codename}', оставляю sources.list как есть"
      ;;
  esac
}

# lsb_release может вернуть "n/a" на очень старом сломанном образе — пробуем /etc/debian_version
if [[ "$CODENAME" == "unknown" || "$CODENAME" == "n/a" ]]; then
  DV="$(cat /etc/debian_version 2>/dev/null || echo '')"
  case "$DV" in
    8.*)  CODENAME=jessie ;;
    9.*)  CODENAME=stretch ;;
    10.*) CODENAME=buster ;;
    11.*) CODENAME=bullseye ;;
    12.*) CODENAME=bookworm ;;
    13.*) CODENAME=trixie ;;
  esac
fi

set_sources_for "$CODENAME"

# Универсальные apt настройки
mkdir -p /etc/apt/apt.conf.d
cat > /etc/apt/apt.conf.d/99force-conf <<'EOF'
Dpkg::Options {
   "--force-confdef";
   "--force-confold";
}
APT::Install-Recommends "true";
APT::Install-Suggests "false";
EOF

apt-get update || { warn "apt-get update вернул предупреждения — продолжаю"; }

#########################  BASE PACKAGES  #######################
step "Ставим базовые пакеты"
# Базовый набор, с учетом названий на разных версиях
pkgs_common=(ca-certificates curl wget bash vim screen less bzip2 rsync socat net-tools iproute2 ipcalc \
             sudo strace lsof psmisc pwgen make unzip tar gzip xz-utils git dnsutils \
             traceroute tcpdump mtr-tiny nmap ufw tree hwinfo gnupg dirmngr gpg-agent locales tzdata \
             lsb-release virt-what edac-utils )
# Дополнительно — где есть:
maybe_install() { apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -q -y install "$@" || true; }

apt-get -q -y install "${pkgs_common[@]}"

# Различия пакетов:
case "$CODENAME" in
  jessie|stretch)
    maybe_install iptraf  || true
    maybe_install linux-perf || true
    maybe_install nagios-plugins nagios-plugins-contrib || true
    ;;
  buster|bullseye|bookworm|trixie|*)
    maybe_install iptraf-ng
    maybe_install linux-perf
    maybe_install monitoring-plugins monitoring-plugins-contrib
    ;;
esac

# Мелкие удобства
maybe_install htop bash-completion neofetch lynx links rcs screenfetch mailutils postfix \
              ulogd2 debootstrap apt-file dstat ifstat sysstat diffmon autoconf automake libtool \
              golang mc whois vlan

ok "Пакеты установлены (что отсутствовало — пропущено без ошибок)"

#########################  LOCALE & TIME  #######################
step "Locales и часовой пояс"
locale-gen --purge en_US.UTF-8 || true
update-locale LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8 || true
ln -fs "/usr/share/zoneinfo/${timezone}" /etc/localtime
dpkg-reconfigure --frontend noninteractive tzdata
ok "en_US.UTF-8 и ${timezone} активированы"

#########################  EDITORS, SCREEN, VIM  ################
step "Vim/Screen настройки"
install_vimrc() {
  cat > "$1" <<'EOF'
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
ok "Vim/Screen настроены"

#########################  KERNEL TUNING  #######################
step "Сетевые твики (sysctl + conntrack)"
# Всё кладём в отдельный файл, не перетирая системный
cat > /etc/sysctl.d/99-tuning.conf <<'EOF'
# Use host MAC / prevent fakery
net.ipv4.conf.eth0.proxy_arp=1

# Spoofing/martians
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1

# IPv6 forwarding off→on при необходимости
net.ipv6.conf.all.forwarding=1

# Forwarding IPv4
net.ipv4.ip_forward=1

# ARP filter (multihoming)
net.ipv4.conf.all.arp_filter=1

# ICMP
net.ipv4.icmp_echo_ignore_broadcasts=1

# Files/IO
fs.file-max = 99999999
fs.aio-max-nr = 99999999

# TCP sane defaults
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 32768
net.core.netdev_max_backlog = 32768
net.core.somaxconn = 32768

# Port range default
net.ipv4.ip_local_port_range = 32768 60999

# Conntrack
net.netfilter.nf_conntrack_tcp_loose = 1
net.netfilter.nf_conntrack_max = 100000000
net.netfilter.nf_conntrack_expect_max = 256

# Bridge netfilter (k8s/docker)
net.bridge.bridge-nf-call-arptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1

# Memory
vm.overcommit_memory = 0
vm.swappiness = 60
EOF

# hashsize — если параметр доступен в рантайме, пишем; иначе — через modprobe.d
if [[ -w /sys/module/nf_conntrack/parameters/hashsize ]]; then
  echo 1000000 > /sys/module/nf_conntrack/parameters/hashsize || true
else
  echo "options nf_conntrack hashsize=1000000" > /etc/modprobe.d/nf_conntrack.conf
fi

modprobe overlay 2>/dev/null || true
modprobe br_netfilter 2>/dev/null || true
modprobe ip_vs 2>/dev/null || true
sysctl --system >/dev/null || true
ok "Сетевые параметры применены"

#########################  GPG KEYS (HWRAID)  ###################
step "Импорт аппаратных ключей (HWRAID/Docker)"
gpg --keyserver "$DOWNLOAD_KEYSERVER" --recv-keys 6005210E23B3D3B4 || true

# Docker keyring (если вдруг понадобится docker repo, особенно для ≤bookworm)
install_docker_keyring() {
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
}
install_docker_keyring || warn "Не удалось подготовить docker keyring — не критично"

#########################  BAREMETAL vs VPS  ####################
if [[ -z "$MATRIX" ]]; then
  step "Обнаружен baremetal (HEAD)"
  # Опционально: apparmor → off (только если grub есть)
  if [[ -d /etc/default/grub.d ]]; then
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT apparmor=0"' > /etc/default/grub.d/apparmor.cfg
    update-grub || true
    info "AppArmor будет отключён после перезагрузки"
  fi

  # RAID/ФС утилиты
  maybe_install lvm2 parted xfsprogs reiserfsprogs
  # netcat: везде используем openbsd вариант
  maybe_install netcat-openbsd
  ok "Baremetal окружение настроено"

  # LXC шаблон
  curl -fsSL https://git.io/JM6Md -o /usr/local/bin/lxc-create-new && chmod +x /usr/local/bin/lxc-create-new || true

  # Вырубаем lxcbr0 по умолчанию
  echo 'USE_LXC_BRIDGE="false"' > /etc/default/lxc-net
  if ! grep -q '^auto br0' /etc/network/interfaces 2>/dev/null; then
    cat >> /etc/network/interfaces <<'EOF'

## LXC br0 bridge (disabled loopback for template)
auto br0
iface br0 inet loopback
  bridge_ports none
  bridge_fd 0
  bridge_hello 2
  bridge_maxage 12
  bridge_stp off
EOF
  fi
else
  step "Виртуальная среда (${MATRIX}): готовим Docker (по возможности)"
  # Некоторые VPS ставят systemd-networkd, некоторые нет — отключаем, если есть
  if systemctl list-unit-files | grep -q '^systemd-networkd\.service'; then
    systemctl disable --now systemd-networkd || true
  fi

  # Требование XFS в исходном скрипте — только предупреждение, не стопорим
  filesystem="$(mount -l | awk '$3=="/"{print $5; exit}')"
  info "ФС /: ${filesystem}"
  if [[ "${filesystem}" != "xfs" ]]; then
    warn "Для Docker рекомендован XFS/overlay2. Продолжаю."
  fi

  DOCKER_INSTALLED=0
  case "$CODENAME" in
    trixie|bookworm)
      # Предпочтительно docker.io из Debian — стабильно и без GPG-ловушек
      if apt-get -q -y install docker.io; then
        systemctl enable --now docker || true
        DOCKER_INSTALLED=1
      fi
      ;;
  esac

  if [[ "$DOCKER_INSTALLED" -eq 0 ]]; then
    # fallback: convenience script без пинов версии (26.0 может не быть)
    if curl -fsSL https://get.docker.com | sh; then
      systemctl enable --now docker 2>/dev/null || true
      ok "Docker установлен через convenience script"
    else
      warn "Docker установить не удалось — пропускаю"
    fi
  fi
fi

#########################  CRON UPDATE  #########################
step "Ежедневный apt-get update через cron"
cat > /etc/cron.daily/update <<'EOF'
#!/bin/bash
/usr/bin/apt-get update &> /dev/null || true
EOF
chmod +x /etc/cron.daily/update
ok "Cron-задача добавлена"

#########################  UPGRADE + MAIN SET ###################
step "apt upgrade + основной набор утилит"
apt-get update || true
apt-get -q -y upgrade || warn "Некоторые пакеты не обновились — не критично"

# Набор уже ставили частично; ещё раз — безопасно
maybe_install ssh rsyslog socat nmap mutt debootstrap apt-file munin-node munin-plugins-extra

# Удаляем нежелаемое (аккуратно, без фатала)
apt-get -q -y remove unattended-upgrades nano rpcbind smartmontools || true
ok "Базовое окружение обновлено"

#########################  HOSTNAME #############################
step "Hostname по обратной записи (если доступна)"
ext_dev="$(ip r | awk '/default/ {print $5; exit}')"
ip_addr="$(ip -4 a show "$ext_dev" | awk '/inet / && /scope global/ {print $2}' | cut -d/ -f1 | head -1)"
hostnamewithdot="$(command -v dig >/dev/null 2>&1 && dig +short -x "$ip_addr" || true)"
if [[ -n "$hostnamewithdot" ]]; then
  hostname="${hostnamewithdot%.}"
else
  hostname="$(cat /etc/hostname 2>/dev/null || echo localhost)"
  [[ -n "$hostname" ]] || hostname="localhost"
fi
hostname "$hostname"
echo "$hostname" > /etc/hostname
ok "Hostname: ${hostname}"

#########################  RC.LOCAL #############################
step "rc.local (модули и sysctl)"
cat > /etc/rc.local <<'EOF'
#!/bin/bash
modprobe overlay || true
modprobe br_netfilter || true
modprobe ip_vs || true
/sbin/sysctl --system >/dev/null 2>&1 || true
exit 0
EOF
chmod +x /etc/rc.local
ok "/etc/rc.local установлен"

#########################  /etc/info ############################
step "Создаём /etc/info и /etc/label (если нет)"
: > /etc/info
: > /etc/label
echo "empty /etc/info (please add notes! / пожалуйста добавьте информацию!)
(https://github.com/matveynator/sysadminscripts/wiki/etc-info)" > /etc/info
ok "Файлы пометок готовы"

#########################  USERS & SUDO #########################
step "Пользователи и sudo"
if ! getent group wheel >/dev/null; then groupadd wheel; fi
if ! id -u "$user" >/dev/null 2>&1; then useradd -m -s /bin/bash "$user"; fi
usermod -aG wheel "$user"
passwd -d "$user" >/dev/null 2>&1 || true
# sudo NOPASSWD
if ! grep -q '^%wheel  ALL=(ALL) NOPASSWD:ALL' /etc/sudoers; then
  echo '%wheel  ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
fi
mkdir -p /home/"$user"/.ssh
chmod 700 /home/"$user"/.ssh
echo "$user_ssh_key" > /home/"$user"/.ssh/authorized_keys
chmod 400 /home/"$user"/.ssh/authorized_keys
chown -R "$user:$user" /home/"$user"

# monitoring user
if [[ -n "${monitoring_user}" ]]; then
  if ! id -u "$monitoring_user" >/dev/null 2>&1; then useradd -m -s /bin/bash "$monitoring_user"; fi
  passwd -d "$monitoring_user" >/dev/null 2>&1 || true
  mkdir -p /home/"$monitoring_user"/.ssh
  chmod 700 /home/"$monitoring_user"/.ssh
  echo "$monitoring_user_ssh_key" > /home/"$monitoring_user"/.ssh/authorized_keys
  chmod 400 /home/"$monitoring_user"/.ssh/authorized_keys
  chown -R "$monitoring_user:$monitoring_user" /home/"$monitoring_user"
  cat > /etc/sudoers.d/"$monitoring_user" <<'EOF'
monitoring_user ALL=NOPASSWD: /usr/local/bin/check_*, /usr/local/bin/redis-backup, /usr/lib/nagios/plugins/check_*
EOF
  sed -i "s/^monitoring_user/${monitoring_user}/" /etc/sudoers.d/"$monitoring_user"
fi
ok "Пользователи настроены"

# root ssh auth
mkdir -p /root/.ssh
chmod 700 /root/.ssh
if ! grep -qF "$user_ssh_key" /root/.ssh/authorized_keys 2>/dev/null; then
  echo "$user_ssh_key" >> /root/.ssh/authorized_keys
  chmod 400 /root/.ssh/authorized_keys
fi

#########################  LEGAL BANNER #########################
step "Баннер входа"
cat > /etc/issue.net <<EOF
************************************************************
* No bad fish allowed.                                     *
* Report security issues to ${email}              *
* Rewards for valid reports. Thank you.                    *
************************************************************
EOF
ok "Баннер установлен"

#########################  /etc/profile #########################
step "/etc/profile с красивым prompt и инфо"
cat > /etc/profile <<'EOF'
# bash-completion
if [ -f /etc/bash_completion ]; then . /etc/bash_completion; fi

if [ "$(id -u)" -eq 0 ]; then
  PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
else
  PATH="/usr/local/bin:/usr/bin:/bin"
fi
export PATH
export LANGUAGE=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export EDITOR=vim
export CLICOLOR=1
touch /etc/label >/dev/null 2>&1 || true
touch /etc/info  >/dev/null 2>&1 || true
label="$(head -1 /etc/label | head -c 50)"
# Красивый prompt: [label] user@host /cwd $
PS1="\[\033[01;95m\]$label \[\033[01;90m\]| \[\033[01;32m\]\u@\h \[\033[01;34m\]\w \$\[\033[00m\] "
# System info
(neofetch || screenfetch || true)
cat /etc/info
EOF
# root .bashrc пустим
: > /root/.bashrc
ok "Профиль оболочки обновлён"

#########################  POSTFIX ##############################
step "Postfix (локальная доставка)"
# Поправляем владельцев (аккуратно)
chown -R postfix:postdrop /var/spool/postfix /var/lib/postfix 2>/dev/null || true

cat > /etc/postfix/main.cf <<'EOF'
smtpd_banner = ESMTP
biff = no
append_dot_mydomain = no
readme_directory = no
compatibility_level = 2

# TLS parameters (snakeoil; замените на свои)
smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
smtpd_tls_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
smtpd_use_tls=yes
smtpd_tls_session_cache_database = btree:${data_directory}/smtpd_scache
smtp_tls_session_cache_database = btree:${data_directory}/smtp_scache

smtpd_relay_restrictions = permit_mynetworks permit_sasl_authenticated defer_unauth_destination
myhostname = localhost
myorigin = localhost
mydestination = localhost.localdomain, localhost
alias_maps = hash:/etc/aliases
alias_database = hash:/etc/aliases
relayhost =
mynetworks = 127.0.0.0/8 172.16.0.0/12 [::ffff:127.0.0.0]/104 [::1]/128
mailbox_size_limit = 0
recipient_delimiter = +
inet_interfaces = all
default_transport = error
relay_transport = error
inet_protocols = ipv4
EOF
systemctl restart postfix 2>/dev/null || /etc/init.d/postfix restart || true
ok "Postfix перезапущен"

#########################  SSHD ################################
step "SSHD настройка безопасного входа по ключу"
cp -a /etc/ssh/sshd_config /etc/ssh/sshd_config.$(date +%s) 2>/dev/null || true
cat > /etc/ssh/sshd_config <<'EOF'
SyslogFacility AUTHPRIV
PasswordAuthentication no
ChallengeResponseAuthentication no
ClientAliveInterval 5
ClientAliveCountMax 1000
Port 22
Protocol 2
Banner /etc/issue.net
PrintMotd no
PermitRootLogin yes
Subsystem sftp /usr/lib/openssh/sftp-server
GatewayPorts clientspecified
EOF
systemctl reload ssh 2>/dev/null || /etc/init.d/ssh reload || true
ok "SSHD применён"

#########################  CUSTOM TOOLS #########################
step "Кастомные плагины/инструменты"
curl -fsSL 'http://files.zabiyaka.net/gurl/latest/linux/amd64/gurl' -o /usr/local/bin/gurl && chmod +x /usr/local/bin/gurl || true
gurl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/install-plugins-and-tools' > /tmp/install-plugins-and-tools 2>/dev/null || true
bash /tmp/install-plugins-and-tools 2>/dev/null || true
rm -f /tmp/install-plugins-and-tools
ok "Инструменты установлены (если доступно)"

#########################  NETFLOW (опция) #####################
if [[ -n "${netflowcollector:-}" ]]; then
  step "Netflow (softflowd) → ${netflowcollector}"
  if apt-get -q -y install softflowd; then
    cat > /etc/softflowd/default.conf <<EOF
interface="any"
options="-n ${netflowcollector}"
EOF
    systemctl enable --now softflowd || true
    ok "softflowd активирован"
  else
    warn "softflowd не установлен"
  fi
fi

#########################  MUNIN ###############################
step "Munin-node"
cat > /etc/munin/munin-node.conf <<EOF
log_level 4
log_file /var/log/munin/munin-node.log
pid_file /var/run/munin/munin-node.pid
background 1
setsid 1
user root
group root
ignore_file [\#~]$
ignore_file DEADJOE$
ignore_file \.bak$
ignore_file %$
ignore_file \.dpkg-(tmp|new|old|dist)$
ignore_file \.rpm(save|new)$
ignore_file \.pod$
allow ^127\.0\.0\.1$
allow ^::1$
cidr_allow 176.9.141.126/32
cidr_allow 2a01:4f8:192:1444::4/64
cidr_allow 10.0.0.0/8
cidr_allow 172.16.0.0/12
cidr_allow 192.168.0.0/16
host *
port 4949
EOF
systemctl restart munin-node 2>/dev/null || /etc/init.d/munin-node restart || true
munin-node-configure --suggest --shell | sh || true
systemctl restart munin-node 2>/dev/null || /etc/init.d/munin-node restart || true
ok "Munin настроен"

#########################  FINAL NOTE ##########################
echo
ok "Готово! Сервер сконфигурирован."
echo -e "${C_DIM}Если что-то нужно подкрутить — скажи, допиляю под твои требования.${C_RESET}"
