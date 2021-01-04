package main

import (
	"fmt"
	"os"
	"os/exec"
)

func main() {
	fmt.Println("Starting PostgreSQL dogu")
	startupSh := exec.Cmd{
		Path:         "/startup.sh",
		Stdout:       os.Stdout,
		Stderr:       os.Stderr,
	}
	startupSh.Run()
}