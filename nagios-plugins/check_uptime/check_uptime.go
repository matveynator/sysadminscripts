package main

import (
  "time"
  "fmt"
  "os"
  "flag"

  "check_uptime/pkg/uptime"
	"github.com/hako/durafmt"
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

func main() {
  parseFlags()

  localUptime, err := uptime.GetUptime()
	localUptimeString := durafmt.Parse(localUptime.Round(60 * time.Second)).String()
	humanCritDuration := durafmt.Parse(CritDuration.Round(60 * time.Second)).String()
	humanWarnDuration := durafmt.Parse(WarnDuration.Round(60 * time.Second)).String()

  if err != nil {
    fmt.Println(err)
    os.Exit(1)
  } else {
    if localUptime <= CritDuration {
      fmt.Printf("CRITICAL: System uptime %s is less than %s.\n", localUptimeString, humanCritDuration )
      os.Exit(2)
    } else if localUptime <= WarnDuration  {
      fmt.Printf("WARNING: System uptime %s is less than %s.\n", localUptimeString, humanWarnDuration )
      os.Exit(3)
    } else  {
      fmt.Printf("OK: System uptime is %s.\n", localUptimeString)
      os.Exit(0)
    }
  }
}
