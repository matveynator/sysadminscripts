package main
  
import (
  "fmt"
  "log"

  client "github.com/nl2go/hrobot-go"
)

func main() {
  robotClient := client.NewBasicAuthClient("K12345678", "PASSSSSSS")

  servers, err := robotClient.IPGetList()
  if err != nil {
    log.Fatalf("error while retrieving server list: %s\n", err)
  }

  fmt.Println(servers)
}
