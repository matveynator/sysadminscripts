#!/bin/bash

# Define variables for user and SSH key
user="matvey"
user_ssh_key="ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAgEAmryyHCe3Bbs1PS10cKTiXBv8tVybXLmftoRBJcxPWaMaTl13sq3EZcU34T5H1P3PA2XdMb4Lt22w8J2CPEzKtEr2ZbXiKdh9oTGwaWJHdXhzP8CuCJHy8ZPWoCHpTnpuXjM3aNXpc2bBhlwm9U58gm09fF3tZ2hGd0elPjUceKa9ETGe0u5XI3/73W6UC1+b0CAKAS6B7b4ZHoUPSFj+ZGTVTZw7ovJiAl9DCOLh0+KFi5MHsqf07xB8yjVSpOig+6XlorI9iaU4GOadcMGVaw4lRXeryL25p1/KCd9pwF0v+B/gKVKRtYjiCfeGoVk91mBJHdyecl31D4aScGknBlAKbhZJQbDWhRvjrK18xRPFBRlPbY9n7DLwotm/Df+wz7TOK4mBgUDYrnRASIn+7RQDIsABa5be05AtAzn6QMxzl7Ai+sTLmGjcfbG3t9RWpumWdA8ZW9cuH/HF78BUKUIGIohIbJvhvGbx9RUINcjhGTMr/hgxXH1QaOfxd5W8N87v9oDi7EiUmIXLtbRHMcXjWqzaI71ydO7bAaAmcsxIQ6OrnbV8GE8IjUDu3nuaeTa8320vW1E/+swLtVF+SxtgR0/iYX9h5FXZcXp1TkNIw0ZfHrY51bxcD9r3pNH69IMNqYjOh29Fh0usenZJZLlPUnmjkjhqGzUhkNlOc/M= MatveyGladkikh"

# Add user and set up SSH keys if user does not exist
if ! id "$user" &>/dev/null; then
    useradd -m -s /bin/bash "$user" && passwd -d "$user"
    mkdir -p "/home/${user}/.ssh" && echo "$user_ssh_key" > "/home/${user}/.ssh/authorized_keys"
    chmod 700 "/home/${user}/.ssh" && chmod 600 "/home/${user}/.ssh/authorized_keys"
    chown -R "$user:$user" "/home/${user}/.ssh"
fi

# Configure root SSH keys
mkdir -p /root/.ssh && echo "$user_ssh_key" >> /root/.ssh/authorized_keys
chmod 700 /root/.ssh

# Configure system limits
cp /etc/security/limits.conf{,.bak.$(date +%s)} &>/dev/null
cat > /etc/security/limits.conf <<EOF
*    soft    nproc   65000
*    hard    nproc   9999999
*    -       nofile  9999999
root - memlock unlimited
EOF

# Update and install base packages:
apt-get update && apt-get -y install curl screen vim rsync git pwgen bash iptraf tcpdump nagios-plugins nagios-plugins-contrib bash-completion munin-plugins-extra htop

# Download and execute additional scripts

#gurl (golang curl with ssl for old machines)
curl -sL 'http://files.matveynator.ru/gurl/latest/linux/amd64/gurl' > /usr/local/bin/gurl && chmod +x /usr/local/bin/gurl

#base system scripts in /usr/local/bin :
gurl 'https://git.io/J4POb' | bash

#/etc/info and /etc/label:
gurl https://raw.githubusercontent.com/matveynator/sysadminscripts/main/label | bash

#monitoing user for nagios:
gurl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/r2d2' | bash

#munin monitoring:
gurl 'https://git.io/Jyi24' | bash

#install atop (it is tricky!):
apt-get -y install atop

# Setup iptables 22 80 443 ports:
gurl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/iptables-install-rules' | bash

# Output completion message
echo "Setup completed successfully!"
