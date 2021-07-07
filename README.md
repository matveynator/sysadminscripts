# Unix sysadmin/devops runbook.
all scripts were tested under Debian Stable (9, 10 etc).

```
                                               _
                 ___                          (_)
               _/XXX\
_             /XXXXXX\_                                    __
X\__    __   /X XXXX XX\                          _       /XX\__      ___
    \__/  \_/__       \ \                       _/X\__   /XX XXX\____/XXX\
  \  ___   \/  \_      \ \               __   _/      \_/  _/  -   __  -  \__/
 ___/   \__/   \ \__     \\__           /  \_//  _ _ \  \     __  /  \____//
/  __    \  /     \ \_   _//_\___     _/    //           \___/  \/     __/
__/_______\________\__\_/________\_ _/_____/_____________/_______\____/_______
                                  /|\
                                 / | \
                                /  |  \
                               /   |   \
                              /    |    \
                             /     |     \
                            /      |      \
                           /       |       \
                          /        |        \
                         /         |         \
```



### PostgreSQL server in docker (any version):
```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-postgresql' > /usr/local/bin/docker-create-postgresql; chmod +x /usr/local/bin/docker-create-postgresql; /usr/local/bin/docker-create-postgresql;

```

### Old and dumb MySQL server in docker (any version):
```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-mysql' > /usr/local/bin/docker-create-mysql; chmod +x /usr/local/bin/docker-create-mysql; /usr/local/bin/docker-create-mysql
```

### New and dumb MariaDB server in docker (any version):
```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-mariadb' > /usr/local/bin/docker-create-mariadb; chmod +x /usr/local/bin/docker-create-mariadb; /usr/local/bin/docker-create-mariadb
```

### Find large directories tool:
```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/find-large-dirs' > /usr/local/bin/find-large-dirs; chmod +x /usr/local/bin/find-large-dirs; /usr/local/bin/find-large-dirs
```


