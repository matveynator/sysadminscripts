# check_uptime

Download latest version here: http://files.zabiyaka.net/nagios_plugins/latest/

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
OK: System uptime is 2 weeks 1 day 18 hours 39 minutes.
```


```
/usr/local/bin/check_uptime -w 60h
WARNING: System uptime is 2 weeks 1 day 18 hours 39 minutes.
```

