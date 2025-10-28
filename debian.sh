#!/bin/bash
#This script is tested under debian 10 (buster) and 11 (bullseye).

#Please change this part to fit your configuration:
############################################################

DOWNLOAD_KEYSERVER=keyserver.ubuntu.com
timezone="Europe/Moscow"
domain="zabiyaka.net";
email="security@zabiyaka.net";
trusted_ipv4_hosts="176.9.141.126 144.76.87.91 95.143.186.117"
trusted_ipv6_hosts="2a01:4f8:192:1444::3 2a01:4f8:192:1444::4"
user="matvey"
user_ssh_key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAE4wDKaXopT7Maw9hhSSDPJxGgvTfzGSjfq7CPo376OxAnEI5gf+HIhgCTpIWfz6jhHBJS16ky789vzaAOScibapzJe7Fnx/JfyEDVtLKEANHb9nlU2pSVOTXQI8QCmUjfSBdW5EEu9OTrWDueN0md51hWH9j4AchOUHlUUDei6txySdddPOy1XJ05uGpV5z2r5F42a8NJs+l2GXhsQnrPQIp7cv7E7FKkYc8LtR9NhNXeoM10Ivb73wGHUEL2sP/ID9IZsnnk3GGiZ1OxomU4R/SvFcA6h6tK/1cR3btzoX1ueXk7XDOdHgqj3sliJhT2Ka8CJmwFxy+20FXeNAQbZy9DPkk3JQg4YgGFpKHFRw00mlVSPWrf4MnDZuLtaML8cBhRCpPq7QZr4A7aOJRGbjUbNV0ZKpgiaioecejHCNu8XKR4BA1whx5fu8VzUsfYNjMI3YLZ+uvcLNfrcMir1/x3IjLMuouOt+EgNsIQTzfdIvDJnNubiyLv9euCc9+hIV1a90uqhv46l3qTIGAExm+9eSqZLpG0v/3GcHda+z2xC8cOcnnjYeL1rrOZiNrav+bf+i3lRD3GIEXKOrbo5zX9tKSym8ehIVYmU5y7K5VZnU121rfzrUhjo0t9UUDvMzdzZmvF2jlEChhXkMsnVy7LPs0Y04E23DHImMQnURKK2FyojZZXK6A23VSIBUlLLTwQ0ZoDhMRa8OKcv+Bukve79HKXpOsMNV4DyZw3sub1SM5mNO73gLb9o7JZNS0BYWWAnLM5OsXEo+wfaYU6vaCB17GDVuSVxB1bjNo5YiIAThea0KLh1IlWHh0rf3mym8Gy6vpTpfhvI1X26zjevSLnZ+V6W+55KzNvxK1gMRS0W3b5J484YRHa0hfZgRjGptEwCYHDQqjNO8uh9cDg2jyHzYHKdSgpOooMutC8hnODK4Ccf309zq4y3hAIWTpXQYpNOjolQtaQ+lk0qym6CpWdGtVZMjFFB24wZHeopWTmrQgIb3BZzZz17/wNRV5XScSFHelcwsjFWvPq6M7W0S5Ih1q8tiwmXIlIXK6RBbDWMoSWAx6u0tXqU2Z42fMTqFP8JQZdUQ1KYARX6B5mew5A24S+A7qgX9fxKOTOe/QzCndFE82+P0UWiXos925TYb8WMIhkt5tAV308B/+UE//6/FwDbNI3GsfqM16GoT1jrbkTTqb0meipfg6X+A4ouf/cjDGSrHYM6kga7OYSxKx4jMnvQ4Q1gKTBoHhQ/Si7o2eySnPX5IM1a9+lHj1dVcb7MTb7/SSBVVOssmLCeYB6Bul7RgiJtN6PWmVpWMB8oZnsL8x0N5ZeysOlfhIeCoeM0PsnGdb/LNH9t/oRZ0KPbObO1jBELE7nfjlQR7oBgtG924an4+LfWF+vO8WnlMU1cM7avihhcEZ7noEquQgO6vSarUurV/FGWym0uLOUaHN6H5FrDSJeVounODIn880p6uP5/5Mw7UhBAifyyqAll3KA1udXTjdp/OU83CpAhGX56PviWCggVjVm2jvHMO3h9LX/DAJYuAfJw7ENOBkgUgx7cwNw52/ZG8NFa8yKfDTeOXj/9GUIH0s+Q3IwxaO26hczqHig3aKWdi0lRoKZSLOk8Qu0ZzquZK3iXl1MmA/DgaHCS+4VBE469agltFQffw== MatveyGladkikh"
monitoring_user="r2d2"
monitoring_user_ssh_key="ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDFpaukSqQbh8xIupopbi335Mhxc725VRmNuITiGf1uG2yorXmOATwRCJ6JaF2iRD3xyKaWDGZn5ijFcbX0Q+31ZwMFl2aUJ4au4qCAIVND1AfI1iXM9/m2fttAicQiyqPS/d8sFbL3VkQXzaolpqUOBMlcMmISwtZMzgQICHETm6Nhm2+TJ/03Q24IRaVuGRH3j6egEC6a4LY2mgbdJrURczsdvn0hpiIHCoISBbj8duTEVw7Si5J5stOaxWhhCvFNXpfb2FHQgkmsMuFhA4QyGUFqkwbWSixvcktQ7ULEDeznyq05njoqmomqujJLtFN5DCjabgoW//R3FApJ0I0uog0sxH9jvr1+yhFxT937YsiztF8XT57Qass5TY9yPGSs5rJoBwEeBzFFSMPl4T3PIGGwc9v0VuZsUDQVWHmMw02g2tk3Uq+P0J7CffcoI5gWG3dE2eWVdgcbFPLiXZo7UdatyfSi/FlFrqmkpo8L/Da5hnmI3HKeSTUuybPYZEf8ETOq8Vq0GjZwVse6+lO7asSiROYpiEEUTrPQzpdU6lY0Of3vra8H7jbEpCyYqLtudsAU4r3IA7A+TRrfYOCagVUzytA2pvuscV0XP4lCMonNhVNpwvPuXTkEdHskW9T4behqSRg7vc4nFWjn2g1FnbaFO7QmLUXU9q9S4kUCnw== nagios@monitor.zabiyaka.net"

############################################################

export DOWNLOAD_KEYSERVER

cp /etc/resolv.conf /etc/resolv.conf.`date +%s` &> /dev/null
cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 2606:4700:4700::1111
nameserver 2606:4700:4700::1001
search $domain
options timeout:3
EOF

export DEBIAN_FRONTEND=noninteractive
apt-get update
if [ $? -ne 0 ]; then
    echo "ERROR: apt-get update (FAILED)"
    exit $?
fi

#install vital packages:
apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -q -y install virt-what lsb-release curl bash apt-transport-https edac-utils locales tzdata apt-transport-https bash gpg dirmngr gpg-agent vim screen wget
if [ $? -ne 0 ]; then
    echo "ERROR: apt-get install (FAILED)"
    exit $?
fi
curl -L 'http://files.zabiyaka.net/gurl/latest/linux/amd64/gurl' > /usr/local/bin/gurl; chmod +x /usr/local/bin/gurl;


debian_version=`lsb_release -cs`

#set virtualization variable ${matrix} (LXC if inside lxc) to check HEAD and non-HEAD executions.
matrix=`virt-what`;
if [[ ! -f "/proc/1/mountinfo" ]]; then
    matrix="chroot"
fi



#set bash default shell:
rm /bin/sh && ln -s /bin/bash /bin/sh


#install en_US.UTF-8 locale:
locale-gen --purge en_US.UTF-8
cat > /etc/default/locale <<EOF
LANG="en_US.UTF-8"
LANGUAGE="en_US:en"
EOF
export CLICOLOR=1
export LC_ALL=C
export EDITOR=vim
export LANGUAGE=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

#set timezone
ln -fs /usr/share/zoneinfo/${timezone} /etc/localtime
dpkg-reconfigure --frontend noninteractive tzdata

#vim
cat > /root/.vimrc <<EOF
runtime! debian.vim
set paste
syntax on
set nomodeline
set encoding=utf-8
filetype plugin indent on
set ignorecase  
set mouse=
EOF

cat > /etc/vim/vimrc <<EOF
runtime! debian.vim
set paste
syntax on
set nomodeline
set encoding=utf-8
filetype plugin indent on
set ignorecase 
set mouse=
EOF

#screen
cat > /etc/screenrc <<EOF
attrcolor b ".I"
shell                 -$SHELL
caption always "%{WB}%?%-Lw%?%{kw}%n*%f %t%?(%u)%?%{WB}%?%+Lw%?%{Wb}"
hardstatus alwayslastline "%{= RY}%H %{BW} %l %{bW} %c %M %d%= \$domain"
activity              "%C -> %n%f %t activity!"
bell                  "%C -> %n%f %t bell!~"
pow_detach_msg        "BYE"
vbell_msg             " *beep* "
EOF


#apt packages:
cat > /etc/apt/apt.conf.d/local <<EOF
Dpkg::Options {
   "--force-confdef";
   "--force-confold";
}
EOF

if [[ "${debian_version}" == "buster" || "${debian_version}" == "wheezy" || "${debian_version}" == "stretch" || "${debian_version}" == "jessie" || "${debian_version}" == "sarge" ]]; then
cp /etc/apt/sources.list /etc/apt/sources.list.`date +%s` &> /dev/null
cat > /etc/apt/sources.list <<EOF
#binary:
deb http://ftp.de.debian.org/debian/ $(lsb_release -cs) main contrib non-free
deb http://security.debian.org/ $(lsb_release -cs)/updates main contrib
#sources:
deb-src http://ftp.de.debian.org/debian/ $(lsb_release -cs) main
deb-src http://security.debian.org/ $(lsb_release -cs)/updates main contrib
EOF
elif [[ "${debian_version}" == "bullseye" ]]; then
cp /etc/apt/sources.list /etc/apt/sources.list.`date +%s` &> /dev/null
cat > /etc/apt/sources.list <<EOF
#binary
deb http://deb.debian.org/debian/ $(lsb_release -cs) main contrib non-free
deb http://deb.debian.org/debian/ $(lsb_release -cs)-updates main contrib non-free
#deb http://deb.debian.org/debian $(lsb_release -cs)-proposed-updates main contrib non-free
deb http://deb.debian.org/debian-security/ $(lsb_release -cs)-security main contrib non-free
#deb http://deb.debian.org/debian/ $(lsb_release -cs)-backports main contrib non-free

#sources
deb-src http://deb.debian.org/debian/ $(lsb_release -cs) main contrib non-free
deb-src http://deb.debian.org/debian/ $(lsb_release -cs)-updates main contrib non-free
#deb-src http://deb.debian.org/debian $(lsb_release -cs)-proposed-updates main contrib non-free
deb-src http://deb.debian.org/debian-security/ $(lsb_release -cs)-security main contrib non-free
#deb-src http://deb.debian.org/debian/ $(lsb_release -cs)-backports main contrib non-free
EOF
elif [[ "${debian_version}" == "bookworm" ]]; then
cp /etc/apt/sources.list /etc/apt/sources.list.`date +%s` &> /dev/null
cat > /etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware
deb-src http://deb.debian.org/debian bookworm main contrib non-free-firmware

deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware
deb-src http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware

deb http://deb.debian.org/debian bookworm-backports main contrib non-free-firmware
deb-src http://deb.debian.org/debian bookworm-backports main contrib non-free-firmware

deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware
deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware
EOF
fi




apt-get update
if [ $? -ne 0 ]; then
    echo "ERROR: apt-get update (FAILED)"
    exit $?
fi


apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -q -y remove atop inxi 
if [ $? -ne 0 ]; then
	echo "ERROR: apt-get remove (FAILED)"
	exit $?
fi

cp /etc/security/limits.conf /etc/security/limits.conf.`date +%s` &> /dev/null
cat > /etc/security/limits.conf <<EOF
*   soft    nproc   65000
*   hard    nproc   9999999
*   -    nofile  9999999
root - memlock unlimited
EOF



#   IMPORTANT: Also adjust hash bucket size for conntracks
#   net/netfilter/nf_conntrack_buckets writeable
#   via /sys/module/nf_conntrack/parameters/hashsize
#
# Hash entry 8 bytes pointer (uses struct hlist_nulls_head)
#  8 * 1 000 000 / 10^6 = 8 MB <- CPU L2 CACHE
echo 1000000 > /sys/module/nf_conntrack/parameters/hashsize

cp /etc/sysctl.conf /etc/sysctl.conf.`date +%s` &> /dev/null
cat > /etc/sysctl.conf <<EOF

#use host mac - dont send fake macs outside (switch will block whole port).
net.ipv4.conf.eth0.proxy_arp=1
net.ipv4.conf.eth0.proxy_arp=1

# Turn on Source Address Verification in all interfaces to
# prevent some spoofing attacks
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.rp_filter=1

# Uncomment the next line to enable packet forwarding for IPv6
#  Enabling this option disables Stateless Address Autoconfiguration
#  based on Router Advertisements for this host
net.ipv6.conf.all.forwarding=1


# Do not accept ICMP redirects (prevent MITM attacks)
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0

# Accept ICMP redirects only for gateways listed in our default
# gateway list (enabled by default)
 net.ipv4.conf.all.secure_redirects = 1

# Do not send ICMP redirects (we are not a router)
net.ipv4.conf.all.send_redirects = 0

# Do not accept IP source route packets (we are not a router)
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
#
# Log Martian Packets
net.ipv4.conf.all.log_martians = 1

#net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.all.disable_ipv6=0 #default

net.ipv4.ip_forward=1
#net.ipv4.ip_forward=0 #default

net.ipv4.conf.all.rp_filter=1
#net.ipv4.conf.all.rp_filter=0 #default

#Allows you to have multiple network interfaces on the same subnet
net.ipv4.conf.all.arp_filter=1
#net.ipv4.conf.all.arp_filter=0 #default

net.ipv4.icmp_echo_ignore_broadcasts=1 
#net.ipv4.icmp_echo_ignore_broadcasts=1 #default

fs.file-max = 99999999
#fs.file-max = 6550940 #default

fs.aio-max-nr = 99999999
#fs.aio-max-nr = 65536 #default

#fs.dir-notify-enable = 0
#fs.dir-notify-enable = 1 #default

#net.ipv4.tcp_keepalive_time = 1800
#net.ipv4.tcp_keepalive_time = 7200 #default

#net.ipv4.tcp_keepalive_probes = 3
#net.ipv4.tcp_keepalive_probes = 9 #default

#net.ipv4.tcp_keepalive_intvl = 15
#net.ipv4.tcp_keepalive_intvl = 75 #default

#net.ipv4.tcp_frto = 0
#net.ipv4.tcp_frto = 2 #default

#net.ipv4.tcp_sack = 1
#net.ipv4.tcp_sack = 1 #default

net.ipv4.tcp_timestamps = 1
#net.ipv4.tcp_timestamps = 1 #default

#net.ipv4.tcp_wmem = 4096 65536 4194304
#net.ipv4.tcp_wmem = 4096 16384 4194304 #default

#net.ipv4.tcp_rmem = 4096 87380 4194304
#net.ipv4.tcp_rmem = 4096 87380 4194304 #default

#net.ipv4.tcp_fin_timeout = 15
#net.ipv4.tcp_fin_timeout = 60 #default

net.ipv4.tcp_tw_reuse = 1
#net.ipv4.tcp_tw_reuse = 0 #default

net.ipv4.tcp_syncookies = 1
#net.ipv4.tcp_syncookies = 0 #default

#net.ipv4.tcp_max_orphans = 9999999
#net.ipv4.tcp_max_orphans = 262144 #default

net.ipv4.tcp_max_syn_backlog = 32768
#net.ipv4.tcp_max_syn_backlog = 2048 #default

#net.ipv4.tcp_synack_retries = 5
#net.ipv4.tcp_synack_retries = 5 #default

#net.ipv4.tcp_syn_retries = 3
#net.ipv4.tcp_syn_retries = 5 #default

#net.core.wmem_max = 16777216
#net.core.wmem_max = 131071 #default

#net.core.rmem_max = 16777216
#net.core.rmem_max = 131071 #default

#net.core.wmem_default = 16777216
#net.core.wmem_default = 124928 #default

#net.core.rmem_default = 16777216
#net.core.rmem_default = 124928 #default

net.core.netdev_max_backlog = 32768
#net.core.netdev_max_backlog = 1000 #default

net.core.somaxconn = 32768
#net.core.somaxconn = 128 #default

#net.ipv4.ip_forward = 1
#net.ipv4.conf.all.forwarding = 1

#net.ipv4.ip_local_port_range = 20000 65535
net.ipv4.ip_local_port_range = 32768 60999 #default

net.netfilter.nf_conntrack_tcp_loose = 1

# Adjusting maximum number of connection tracking entries possible
# Conntrack element size 288 bytes found in /proc/slabinfo
#  "nf_conntrack" <objsize> = 288
# 288 * 100 000 000 / 10^6 = 28.8 GB RAM
net.netfilter.nf_conntrack_max = 100000000
net.netfilter.nf_conntrack_expect_max = 256

#kubernates modprobe br_netfilter
net.bridge.bridge-nf-call-arptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1

#kernel.shmall = 268435456
#kernel.shmall = 2097152 #default

#kernel.shmmax = 268435456
#kernel.shmmax = 33554432 #default

#redis server:
#vm.overcommit_memory = 1
vm.overcommit_memory = 0 #default

#vm.swappiness = 0
vm.swappiness = 60 #default
EOF



#hwraid
gpg --keyserver keyserver.ubuntu.com --recv-keys 6005210E23B3D3B4
if [ $? -ne 0 ]; then
    echo "ERROR: GPG network key import (FAILED)"
    exit $?
fi

gpg --keyserver keyserver.ubuntu.com --recv-keys 7EA0A9C3F273FCD8
if [ $? -ne 0 ]; then
    echo "ERROR: GPG network key import (FAILED)"
    exit $?
fi




if [ "$matrix" == "" ]; 
	then
		#running on phisical head machine      
		
		#disable apparmor as it is unstable now
		mkdir -p /etc/default/grub.d
		echo 'GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT apparmor=0"' | tee /etc/default/grub.d/apparmor.cfg
		update-grub;
		
		#hardware raid
		
		apt-add-repository "deb http://hwraid.le-vert.net/debian wheezy main"
  		

		if [ "${debian_version}" == "bookworm" ]; then
		apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -q -y install ncat socat atop
		fi
  
		if [ "${debian_version}" == "buster" ]; then
			#backports (newer kernel)
			apt-add-repository "deb http://deb.debian.org/debian $(lsb_release -cs)-backports main"
		fi

		apt-get update;
		if [ $? -ne 0 ]; then
		    echo "ERROR: apt update (FAILED)"
		    exit $?
		fi
		apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -q -y install lxc bridge-utils crashme parted lvm2 bridge-utils xfsprogs reiserfsprogs 
		if [ $? -ne 0 ]; then
		    echo "ERROR: apt install of hardware utilites (FAILED)"
		    exit $?
		fi
		
		
			apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -q -y install netcat-openbsd
			if [ $? -ne 0 ]; then
				echo "ERROR: apt install of hardware utilites (FAILED)"
				exit $?
			fi


		if [ "${debian_version}" == "buster" ]; then
			apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -q -y install linux-image-amd64/buster-backports
			if [ $? -ne 0 ]; then
				echn "ERROR: apt install of buster backports kernel (FAILED)"
				exit $?
			fi
		fi

		gurl 'https://git.io/JM6Md' > /usr/local/bin/lxc-create-new; chmod +x /usr/local/bin/lxc-create-new;
                

#disable lxcbr0 bridge
echo 'USE_LXC_BRIDGE="false"' > /etc/default/lxc-net
		
cat >> /etc/network/interfaces <<EOF

##ENABLE LXC br0 BRIDGE
auto br0
iface br0 inet loopback
bridge_ports none
bridge_fd 0
bridge_hello 2
bridge_maxage 12
bridge_stp off
EOF

	else 
		#running inside virtual server

		#disable systemd-networkd as it is A SHIT:
		systemctl disable systemd-networkd
		if [ $? -ne 0 ]; then
		    echo "ERROR: disable systemd-networkd (FAILED)"
		    exit $?
		fi

		filesystem=`mount -l | grep "on / type" |awk  '{print$5}'`
		if [ "${filesystem}" != "xfs" ] 
		then
			echo "You MUST use ONLY XFS filesystem for Docker."
		else

		#docker
		mkdir -p /etc/docker
		cp /etc/docker/daemon.json /etc/docker/daemon.json.`date +%s` &> /dev/null
		cat > /etc/docker/daemon.json <<EOF
{
	"storage-driver": "overlay2"
}
EOF
		apt-add-repository "deb https://download.docker.com/linux/debian $(lsb_release -cs) stable"
		
		apt-get update
		if [ $? -ne 0 ]; then
		    echo "ERROR: apt update (FAILED)"
		    exit $?
		fi
		curl -fsSL https://get.docker.com | sh -s -- --version 26.0
		if [ $? -ne 0 ]; then
		    echo "ERROR: apt install of docker (FAILED)"
		    exit $?
		fi
		fi
fi

#notify about updates
cat > /etc/cron.daily/update <<EOF
#!/bin/bash
/usr/bin/apt-get update  &> /dev/null
EOF
chmod +x /etc/cron.daily/update

#default set of packages
apt-get update
if [ $? -ne 0 ]; then
    echo "ERROR: apt update (FAILED)"
    exit $?
fi
apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -q -y upgrade
if [ $? -ne 0 ]; then
    echo "ERROR: apt upgrade (FAILED)"
    exit $?
fi
apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -q -y install ssh vim ulogd2 hwinfo rsyslog mailutils postfix tree curl screen net-tools rcs golang less bzip2 rsync socat nmap dns-browse mutt iproute2 vlan postfix debootstrap apt-file dstat ifstat sysstat diffmon sudo strace  lsof at autoconf automake libtool fakeroot psmisc pwgen ipcalc ftp make lftp unzip lynx links  mc curl gitk bash trickle mtr-tiny stress libwww-perl tcpdump  iptraf nagios-plugins nagios-plugins-contrib bash-completion bc htop lshw linux-perf-* bc tcptraceroute iptables whois mailutils munin-node munin-plugins-extra screenfetch ufw
if [ $? -ne 0 ]; then
    echo "ERROR: apt install of main utilites (FAILED)"
    exit $?
fi
apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -q -y remove unattended-upgrades nano rpcbind smartmontools
if [ $? -ne 0 ]; then
    echo "ERROR: apt remove of bad progs (FAILED)"
    exit $?
fi

#hostname check and setup
ext_dev=`ip r |grep default |awk '{print$5}'`
ip=`ip a |grep 'inet ' | grep ${ext_dev}| grep 'scope global' |awk '{print$2}' |awk -F'/' '{print$1}'`
prefix=`ip a |grep 'inet ' | grep ${ext_dev} |grep 'scope global' |awk '{print$2}' |awk -F'/' '{print$2}'`
hostnamewithdot=`dig +short -x $ip`
if [ $? -ne 0 ];
then
        #ERROR: dig  failed - using old hostname from /etc/hostname
        hostname=`cat /etc/hostname`
	if [ "${hostname}" eq "" ] 
		then	
		hostname="localhost"
	fi
else
        hostname=${hostnamewithdot%?}
fi
hostname $hostname
echo $hostname > /etc/hostname


#rc.local
cp /etc/rc.local /etc/rc.local.`date +%s` &> /dev/null
cat > "/etc/rc.local" <<EOF
#!/bin/bash
modprobe overlay; 
modprobe br_netfilter;
modprobe ip_vs;
/sbin/sysctl -p
EOF
chmod +x /etc/rc.local

cp /etc/info /etc/info.`date +%s` &> /dev/null
cat > /etc/info <<EOF
empty /etc/info (please add notes! / пожалуйста добавьте инофрмацию!) 
(https://github.com/matveynator/sysadminscripts/wiki/etc-info)
EOF

#add users
groupadd wheel
useradd ${user}
usermod -G wheel ${user}
usermod -s /bin/bash ${user}
passwd -d ${user}
grep -v '%wheel  ALL=(ALL) NOPASSWD:ALL' /etc/sudoers > /tmp/spool
cat /tmp/spool > /etc/sudoers
echo '%wheel  ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
mkdir -p /home/${user}/.ssh
cat > /home/${user}/.ssh/authorized_keys <<EOF
${user_ssh_key}
EOF
chown ${user}:${user} /home/${user} -R
chmod 700 /home/${user}
chmod 700 /home/${user}/.ssh
chmod 400 /home/${user}/.ssh/authorized_keys


if [ "${monitoring_user}" != "" ] 
then
#add monitoring user (bot)
cat > /etc/sudoers.d/${monitoring_user} <<EOF
${monitoring_user} ALL=NOPASSWD: /usr/local/bin/check_*, /usr/local/bin/redis-backup, /usr/lib/nagios/plugins/check_*
EOF
useradd ${monitoring_user}
usermod -s /bin/bash ${monitoring_user}
passwd -d ${monitoring_user}
mkdir -p /home/${monitoring_user}/.ssh
cat > /home/${monitoring_user}/.ssh/authorized_keys <<EOF
${monitoring_user_ssh_key}
EOF
chown ${monitoring_user}:${monitoring_user} /home/${monitoring_user} -R
chmod 700 /home/${monitoring_user}
chmod 700 /home/${monitoring_user}/.ssh
chmod 400 /home/${monitoring_user}/.ssh/authorized_keys
fi

#root
mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat >> /root/.ssh/authorized_keys <<EOF
${user_ssh_key}
EOF

cp /etc/issue.net /etc/issue.net.`date +%s` &> /dev/null
cat > /etc/issue.net <<EOF
************************************************************
* No bad fish allowed. We appreciate your reports of       *
* insecurity issues to ${email} We will    *
* pay for successful insecurity reports. Thank you.        *
************************************************************

EOF

cp /etc/profile /etc/profile.`date +%s` &> /dev/null
cat > /etc/profile <<EOF
# enable bash completion in interactive shells
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

if [ "\`id -u\`" -eq 0 ]; then
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
touch /etc/label &> /dev/null
touch /etc/info &> /dev/null
label=\`cat /etc/label |head -1 | head -c 50\`;
export PS1="\[\033[01;91m\]\$label \[\033[01;90m\]| \[\033[01;32m\]\u@\h\[\033[01;34m\] \w $\[\033[00m\] "
#system additional information
screenfetch
cat /etc/info;
EOF

#root bashrc cleanup
cp /root/.bashrc /root/.bashrc.`date +%s` &> /dev/null
cat /dev/null > /root/.bashrc

#POSTFIX configs
chown -R postfix:postdrop /var/spool/postfix
chown -R postfix:postdrop /var/lib/postfix

cat /etc/postfix/main.cf |grep -v default_transport |grep -v relay_transport |grep -v inet_protocols > /tmp/posfix_configs
cat /tmp/posfix_configs > /etc/postfix/main.cf
cat > /etc/postfix/main.cf <<EOF
smtpd_banner = ESMTP
biff = no
append_dot_mydomain = no
readme_directory = no
compatibility_level = 2

# TLS parameters
smtpd_tls_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
smtpd_tls_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
smtpd_use_tls=yes
smtpd_tls_session_cache_database = btree:\${data_directory}/smtpd_scache
smtp_tls_session_cache_database = btree:\${data_directory}/smtp_scache

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

/etc/init.d/postfix restart

#sshd config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.`date +%s` &> /dev/null
cat > /etc/ssh/sshd_config <<EOF
SyslogFacility AUTHPRIV
PasswordAuthentication no
ChallengeResponseAuthentication no
ClientAliveInterval 5
ClientAliveCountMax     1000
Port 22
Protocol 2
Banner /etc/issue.net
PrintMotd no
PermitRootLogin yes
Subsystem sftp /usr/lib/openssh/sftp-server
GatewayPorts clientspecified
EOF

cp /etc/ssh/ssh_config /etc/ssh/ssh_config.`date +%s` &> /dev/null
cat > /etc/ssh/ssh_config <<EOF
Host *
PermitLocalCommand yes
EOF

#apply configuration
/etc/init.d/ssh reload

#install custom nagios plugins and tools
gurl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/install-plugins-and-tools' > /tmp/install-plugins-and-tools; bash /tmp/install-plugins-and-tools; rm -f /tmp/install-plugins-and-tools;

#netflow monitoring functionality
if [ "${netflowcollector}" != "" ]
then
apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" -q -y install softflowd
if [ $? -ne 0 ]; then
    echo "ERROR: apt install of softflowd (FAILED)"
    exit $?
fi
#netflow collector
cat > /etc/softflowd/default.conf <<EOF
interface="any"
options="-n $netflowcollector"
EOF
systemctl enable softflowd
systemctl start softflowd
systemctl restart softflowd
fi

#munin graphs
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
/etc/init.d/munin-node restart
munin-node-configure --suggest --shell | sh
/etc/init.d/munin-node restart
mail -s "new server configured" ${email} < /etc/hostname
echo 'configuration finished'


