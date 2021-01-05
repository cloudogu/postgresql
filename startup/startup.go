package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strconv"
)

func main() {
	fmt.Println("Starting PostgreSQL dogu")

	PgdataPath := os.Getenv("PGDATA")

	err := setPostgresAsPgdataOwner(PgdataPath)
	if err != nil {
		log.Fatalf("Could not set postgres as owner of %s: %v", PgdataPath, err)
	}

	startupSh := exec.Cmd{
		Path:         "/startup.sh",
		Stdout:       os.Stdout,
		Stderr:       os.Stderr,
	}
	startupSh.Run()
}

func setPostgresAsPgdataOwner(pgdataPath string) error {
	PostgresUser, err := user.Lookup("postgres")
	if err != nil {
		return fmt.Errorf("could not get postgres user: %v", err)
	}
	PostgresUid, err := strconv.Atoi(PostgresUser.Uid)
	err = filepath.Walk(pgdataPath, func(path string, info os.FileInfo, err error) error {
		os.Chown(path, PostgresUid, PostgresUid)
		return err
	})
	return err
}