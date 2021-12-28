<p>
  <img src="https://repository-images.githubusercontent.com/302284801/4ad5ca04-f55a-4eac-9d1a-50260aa2c005" width="75%">
</p>

# Oldschool UNIX sysadmin KUNG-FU.
All scripts were tested under Debian Stable (9, 10, 11 etc).

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

### Debian Stable (9,10,11):
```
curl -L https://git.io/JWhaD | sudo bash
```

### Install all tools:
```
curl -L 'https://git.io/J4POb' | sudo bash
```

### PostgreSQL in docker: 
```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-postgresql' > /usr/local/bin/docker-create-postgresql; chmod +x /usr/local/bin/docker-create-postgresql; sudo /usr/local/bin/docker-create-postgresql;
```

### MySQL in docker:
```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-mysql' > /usr/local/bin/docker-create-mysql; chmod +x /usr/local/bin/docker-create-mysql; sudo /usr/local/bin/docker-create-mysql
```

### MariaDB in docker:
```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-mariadb' > /usr/local/bin/docker-create-mariadb; chmod +x /usr/local/bin/docker-create-mariadb; sudo /usr/local/bin/docker-create-mariadb
```

### Find large directories tool:
```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/find-large-dirs' > /usr/local/bin/find-large-dirs; chmod +x /usr/local/bin/find-large-dirs; sudo /usr/local/bin/find-large-dirs
```

### Wildcard acme.sh SSL cert via Hetzner DNS:

```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/acme.sh-wildcard-hetzner-dns' > /usr/local/bin/acme.sh-wildcard-hetzner-dns; chmod +x /usr/local/bin/acme.sh-wildcard-hetzner-dns; sudo /usr/local/bin/acme.sh-wildcard-hetzner-dns
```

### Change Let's encrypt to ZeroSSL with acme.sh:
```
curl -L 'https://git.io/JaXBn' > /usr/local/bin/certbot-to-acme.sh; chmod +x  /usr/local/bin/certbot-to-acme.sh; certbot-to-acme.sh
```

### LXC
```
curl -L 'https://git.io/JM6Md' > /usr/local/bin/lxc-create-new; chmod +x /usr/local/bin/lxc-create-new;
```
