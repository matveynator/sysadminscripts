package main

import (
  "time"
  "fmt"
  "os"
  "flag"

  "golang.org/x/sys/unix"
)

var CritDuration, WarnDuration time.Duration
var VERSION string

func parseFlags()  {
  flagVersion := flag.Bool("version", false, "Output version information.")
  flag.DurationVar(&CritDuration, "c", 1*time.Hour, "Set CRITICAL duration. Valid time units are: 's' (second), 'm' (minute), 'h' (hour).")
  flag.DurationVar(&WarnDuration, "w", 24*time.Hour, "Set WARNING duration. Valid time units are: 's' (second), 'm' (minute), 'h' (hour).")
  //process all flags
  flag.Parse()

  if *flagVersion  {
    if VERSION != "" {
      fmt.Println("Version:", VERSION)
    }
    os.Exit(0)
  }

}

func getUptime() (time.Duration, error) {
  var info unix.Sysinfo_t
  if err := unix.Sysinfo(&info); err != nil {
    return time.Duration(0), err
  }
  return time.Duration(info.Uptime) * time.Second, nil
}

func main() {
  parseFlags()
  uptime, err := getUptime()
  if err != nil {
    fmt.Println(err)
    os.Exit(1)
  } else {
    if uptime <= CritDuration {
      fmt.Printf("CRITICAL: System uptime %s is less than %s.\n", uptime, CritDuration )
      os.Exit(2)
    } else if uptime <= WarnDuration  {
      fmt.Printf("WARNING: System uptime %s is less than %s.\n", uptime, WarnDuration )
      os.Exit(3)
    } else  {
      fmt.Printf("OK: System uptime is %s.\n", uptime)
      os.Exit(0)
    }
  }
}
