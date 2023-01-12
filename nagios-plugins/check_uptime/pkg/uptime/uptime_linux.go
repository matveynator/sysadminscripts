//go:build ( linux || android )

package uptime

import(
  "time"
  "golang.org/x/sys/unix"
)

func GetUptime() (time.Duration, error) {
  var info unix.Sysinfo_t
  if err := unix.Sysinfo(&info); err != nil {
    return time.Duration(0), err
  }
  return time.Duration(info.Uptime) * time.Second, nil
}
