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


```

### get curl-go (golang version of curl with embedded SSL):
```
curl -L 'http://files.matveynator.ru/curl-go/latest/linux/amd64/curl-go' > /usr/local/bin/curl-go; chmod +x /usr/local/bin/curl-go;
```

### Debian Stable (9,10,11):
```
curl-go https://git.io/JWhaD | bash
```

### Install all tools:
```
curl-go 'https://git.io/J4POb' > /tmp/tools; sh /tmp/tools; rm -f /tmp/tools; 
```

### Tools + info + label + fixing postfix/mysql permissions
```
curl-go https://raw.githubusercontent.com/matveynator/sysadminscripts/main/cleanup |bash
```

### Monitoring user setup:
```
curl-go 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/r2d2' | bash
```

### Munin
```
curl-go 'https://git.io/Jyi24' | bash
```

### PostgreSQL in docker: 
```
curl-go 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-postgresql' > /usr/local/bin/docker-create-postgresql; chmod +x /usr/local/bin/docker-create-postgresql; sudo /usr/local/bin/docker-create-postgresql;
```

### MySQL in docker:
```
curl-go 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-mysql' > /usr/local/bin/docker-create-mysql; chmod +x /usr/local/bin/docker-create-mysql; sudo /usr/local/bin/docker-create-mysql
```

### MariaDB in docker:
```
curl-go 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-mariadb' > /usr/local/bin/docker-create-mariadb; chmod +x /usr/local/bin/docker-create-mariadb; sudo /usr/local/bin/docker-create-mariadb
```

### Find large directories tool:
```
curl-go 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/find-large-dirs' > /usr/local/bin/find-large-dirs; chmod +x /usr/local/bin/find-large-dirs; sudo /usr/local/bin/find-large-dirs
```

### Wildcard acme.sh SSL cert via Hetzner DNS:

```
curl-go 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/acme.sh-wildcard-hetzner-dns' > /usr/local/bin/acme.sh-wildcard-hetzner-dns; chmod +x /usr/local/bin/acme.sh-wildcard-hetzner-dns; sudo /usr/local/bin/acme.sh-wildcard-hetzner-dns
```

### Change Let's encrypt to ZeroSSL with acme.sh:
```
curl-go 'https://git.io/JaXBn' > /usr/local/bin/certbot-to-acme.sh; chmod +x  /usr/local/bin/certbot-to-acme.sh; certbot-to-acme.sh
```

### LXC
```
curl-go 'https://git.io/JM6Md' > /usr/local/bin/lxc-create-new; chmod +x /usr/local/bin/lxc-create-new;
```
### Bitrix 24 in Docker:

```
curl-go https://raw.githubusercontent.com/matveynator/bitrix24-docker/main/install.sh | bash
```

## Pritunl OpenVPN:
```
curl-go https://raw.githubusercontent.com/matveynator/sysadminscripts/main/pritunl | bash
```
