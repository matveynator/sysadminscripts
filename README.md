# Oldschool UNIX sysadmin notes and scripts.
All scripts were tested under Debian Stable (9, 10 etc).

![#f03c15](https://via.placeholder.com/15/f03c15/000000?text=+) 
![#c5f015](https://via.placeholder.com/15/c5f015/000000?text=+)
![#1589F0](https://via.placeholder.com/15/1589F0/000000?text=+)

```

             _      
            (_)     
 _   _ _ __  ___  __
| | | | '_ \| \ \/ /
| |_| | | | | |>  < 
 \__,_|_| |_|_/_/\_\  WHERE THERE IS A SHELL, WHERE IS A WAY.


                                      `::..   .
                       `?XXX.  `T{/:.   %X/!!x "?x.
                         "4{7@( '!+!!X(:.`4!!X!x.?h7h
                     `!(:. ~!!!f(~!!!+!!{{.'~+h!tX!!?hh:.
                '`X!.  !(d!X!!H!?{{``"!:?{{!{X*!?tX!!H*))h.
              ...  '!X(!X!{{?@f!!!{!{x.!!%!!!%!!!)@Thh!!X)!).
               ^!!!{:!(((!!: ~((({!!!h+!{{!X!+%?+{!!?!+)!+X(!+
           -    `\tXX{(~!!!!!:.!.%%(!!!!!!!!!X!))!!!!X%``%!!!(>
           ^X>:x. {!!!!X: ~!!*!{!!!{!~!X!)%!{!!!)?@!!!?!)?!!!>~
             `X(!!:!!!{{(!!.)!%(:\!!:%~!~\!t!! `H!)~~!!!!!!(?@
              `!X: `)!!!C44XX!!!.%%.X:>-> %!!X! /!~!.'!> !S!!!
          +{..  \X%\.'{??X!!!t!!~!!{!~!~'.!~~~ -~` {> !~ /!X`
            `X!XXM!!4!%\(4!!!!%(`,zccccd$$$$$$$$$ccx ` .~
              "XLS@!)!!%L44X!!! d$$$$$$$$$$$$$$$$$$$,  '^
               `!X?%:!!??X!4?*';$$$$$$$$$$$$$$$$$$$$$
              `iXM:!!?Xt!XH!!! 9$$$$$$$$$$$$$$$$$$$$$
               `X3tiXS#?WH!X!! $$$$$$$$$$$$$$$$$$$$$$
               .MX?*StXX?X!!W? $$$$$$$>?$$$$$$$$$$$$
                8??M%T%' r `  ;$$$$$$$$$,?$$$$$$$$$F
                'StMX!': J$$d$$$$$$$$$$$$h ?$$$$$$"
                 tM9MH d$$$$$$$$$$$$$$C???r{$$$F,r
                 4M?t':$$$$$$$$$$$$$$$$h. $$$,cP"
                 'M>.d$$$$$$$$$$$$$$$$$>d$$${.,
                  ,d$$$$$$$$$$$$$$$$$'cd$$$$r"
                  `$$$$$$$$$$$$$$$??$Jcii`?$h
                   $$$$$$$$$$$$$F,;;, "?h,`$$h
                  j$$$$$$$$$$$$$.CC>>>>c`"  `"        ..,g q,
               .'!$$$$$$$$$$$$$' `''''''            aq`?g`$.Bk
           ,- '  "?$$$$$$$$$$$$$$d$$$$$c, .         .)od$$$$$$
      , -'           `""'   `"?$$$$$$$$$??=      .d$$$$$$$$F'
    ,'                           `??$$P       .ed$$P""   `
   ,                                `.      z$$$"
   `:dbe,                          x,/    e$$F'
   :$$$$P'`>                       $F  z$$$"
  d$$$P"'  >                       $Fe$$$"
.$$$?F     ;                       $$$$"
$$$$$$eeu. >                       >P"
 `""???$$$$$eu,._''uWb,            )
           `""??$P$$$$$$b.         :
            >     ?$$$"'           {
            F      `"              `:
            >                       `>
            >                        ?
           J                          :
           X                ..  .     ?
           "{ 4{!~;/'!>{`~{>~.>! ~! '"
            '>!>=.%=.;~~>~4~`{'>>>~!
             4'!/>!\\!{~~:/{;!{;`;/=':
             `=;!~:`~!>{.-; "(>=.':!;'
              :;=.~{`;`~>!~> ?!/>>~!!{'
              ~:~'!!;`;`~:>); ;(.uJL!~~
                >L.(.:,L;L:-+d$$$$$$
                :4$$$$$$$L   ?$$#$$$>
                 '$$$B$$$>    $$$MB$&
                  $$$$$$$      $$$@$F
                  `$$$$$$>     R$$$$
                   $$$$$$     {$$@$P
                   $R$$$R     `!)=!>
                   $$$6T       $$$$'
                   $$R$B      ;$$$F,._
                   !=!(!    .'        ``= .
                   $$$$F    (.             '\
                 ,{$$$$(      ``~'`` --:.._.,)
                ;   ``  `-.
                (          "\.
                 ` -{._       ".
                       `~:,._ .:

GOOD THINGS HAPPEN FOR THOSE WHO WAIT.
```

### Debian 10 BUSTER

```
curl -L https://git.io/JWhaD |bash
```

### PostgreSQL in docker (any version):
```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-postgresql' > /usr/local/bin/docker-create-postgresql; chmod +x /usr/local/bin/docker-create-postgresql; /usr/local/bin/docker-create-postgresql;

```

### MySQL in docker (any version):
```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-mysql' > /usr/local/bin/docker-create-mysql; chmod +x /usr/local/bin/docker-create-mysql; /usr/local/bin/docker-create-mysql
```

### MariaDB in docker (any version):
```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/docker-create-mariadb' > /usr/local/bin/docker-create-mariadb; chmod +x /usr/local/bin/docker-create-mariadb; /usr/local/bin/docker-create-mariadb
```

### Find large directories tool:
```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/find-large-dirs' > /usr/local/bin/find-large-dirs; chmod +x /usr/local/bin/find-large-dirs; /usr/local/bin/find-large-dirs
```

### Wildcard acme.sh SSL cert via Hetzner DNS:

```
curl 'https://raw.githubusercontent.com/matveynator/sysadminscripts/main/acme.sh-wildcard-hetzner-dns' > /usr/local/bin/acme.sh-wildcard-hetzner-dns; chmod +x /usr/local/bin/acme.sh-wildcard-hetzner-dns; /usr/local/bin/acme.sh-wildcard-hetzner-dns
```

### Install custom tools and nagios plugins

```
curl -L 'https://git.io/J4POb' | bash
```

