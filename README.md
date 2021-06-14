# Unix sysadmin/devops runbook.
all scripts were tested under Debian Stable (9, 10 etc).

![](https://raw.githubusercontent.com/matveynator/sysadminscripts/main/chicha.jpg | width=400)



### PostgreSQL server in docker (any version):
```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-postgresql' > /usr/local/bin/docker-create-postgresql; chmod +x /usr/local/bin/docker-create-postgresql; /usr/local/bin/docker-create-postgresql;

```

### Old dumb MySQL server in docker (any version):
```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-mysql' > /usr/local/bin/docker-create-mysql; chmod +x /usr/local/bin/docker-create-mysql; /usr/local/bin/docker-create-mysql
```

### New dumb MariaDB server in docker (any version):
```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-mariadb' > /usr/local/bin/docker-create-mariadb; chmod +x /usr/local/bin/docker-create-mariadb; /usr/local/bin/docker-create-mariadb
```

### Find large file directories
```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/find-large-dirs' > /usr/local/bin/find-large-dirs; chmod +x /usr/local/bin/find-large-dirs; /usr/local/bin/find-large-dirs
```


