# check_uptime

Download latest version here: http://files.matveynator.ru/nagios_plugins/latest/

```
/usr/local/bin/check_uptime -h
Usage of /usr/local/bin/check_uptime:
  -c duration
    	Set CRITICAL duration. Valid time units are: 's' (second), 'm' (minute), 'h' (hour). (default 1h0m0s)
  -version
    	Output version information.
  -w duration
    	Set WARNING duration. Valid time units are: 's' (second), 'm' (minute), 'h' (hour). (default 24h0m0s)
```

```
/usr/local/bin/check_uptime 
OK: System uptime is 59h15m34s.
```


```
/usr/local/bin/check_uptime -w 60h
WARNING: System uptime 59h15m40s is less than 60h0m0s.
```

