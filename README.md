<p>
  <img src="https://repository-images.githubusercontent.com/302284801/3c843e8b-085b-4833-aa09-00e697ae81e1" width="50%">
</p>

# UNIX sysadmin KUNG-FU.
Debian addicted.

![#f03c15](https://via.placeholder.com/15/f03c15/000000?text=+) 
![#c5f015](https://via.placeholder.com/15/c5f015/000000?text=+)
![#1589F0](https://via.placeholder.com/15/1589F0/000000?text=+)

```

             _      
            (_)     
 _   _ _ __  ___  __
| | | | '_ \| \ \/ /
| |_| | | | | |>  < 
 \__,_|_| |_|_/_/\_\  WHERE, THERE IS A SHELL, WHERE IS A WAY.

How to add new sysadmin kung-fu script or fix some problem?

- Fork it
- Create your feature branch (git checkout -b my-new-feature)
- Commit your changes (git commit -am 'Added some feature')
- Push to the branch (git push origin my-new-feature)
- Create new Pull Request

```

### [WiKi](https://github.com/matveynator/sysadminscripts/wiki)

### get gurl (golang version of curl with embedded SSL):
```
curl -L 'http://files.matveynator.ru/gurl/latest/linux/amd64/gurl' > /usr/local/bin/gurl; chmod +x /usr/local/bin/gurl;
```

### minimal setup for debian or ubuntu etc (base scripts, monitoring, label):
```
apt-get update; apt-get -y install curl bash; curl -sL 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/any-debian.sh' |bash;
```


### Debian Stable (9,10,11):
```
gurl https://git.io/JWhaD | bash
```

### Install all tools:
```
gurl 'https://git.io/J4POb' > /tmp/tools; sh /tmp/tools; rm -f /tmp/tools; 
```

### Info + label
```
gurl https://raw.githubusercontent.com/matveynator/sysadminscripts/main/label |bash
```

### Monitoring user setup:
```
gurl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/r2d2' | bash
```

### Munin
```
gurl 'https://git.io/Jyi24' | bash
```

### PostgreSQL in docker: 
```
gurl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-postgresql' > /usr/local/bin/docker-create-postgresql; chmod +x /usr/local/bin/docker-create-postgresql; sudo /usr/local/bin/docker-create-postgresql;
```

### MySQL in docker:
```
gurl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-mysql' > /usr/local/bin/docker-create-mysql; chmod +x /usr/local/bin/docker-create-mysql; sudo /usr/local/bin/docker-create-mysql
```

### MariaDB in docker:
```
gurl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-mariadb' > /usr/local/bin/docker-create-mariadb; chmod +x /usr/local/bin/docker-create-mariadb; sudo /usr/local/bin/docker-create-mariadb
```

### Find large directories tool:
```
gurl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/find-large-dirs' > /usr/local/bin/find-large-dirs; chmod +x /usr/local/bin/find-large-dirs; sudo /usr/local/bin/find-large-dirs
```

### Wildcard acme.sh SSL cert via Hetzner DNS:

```
gurl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/acme.sh-wildcard-hetzner-dns' > /usr/local/bin/acme.sh-wildcard-hetzner-dns; chmod +x /usr/local/bin/acme.sh-wildcard-hetzner-dns; sudo /usr/local/bin/acme.sh-wildcard-hetzner-dns
```

### Change Let's encrypt to ZeroSSL with acme.sh:
```
gurl 'https://git.io/JaXBn' > /usr/local/bin/certbot-to-acme.sh; chmod +x  /usr/local/bin/certbot-to-acme.sh; certbot-to-acme.sh
```

### LXC
```
gurl 'https://git.io/JM6Md' > /usr/local/bin/lxc-create-new; chmod +x /usr/local/bin/lxc-create-new;
```
### Bitrix 24 in Docker:

```
gurl https://raw.githubusercontent.com/matveynator/bitrix24-docker/main/install.sh | bash
```

## Pritunl OpenVPN:
```
gurl https://raw.githubusercontent.com/matveynator/sysadminscripts/main/pritunl | bash
```
