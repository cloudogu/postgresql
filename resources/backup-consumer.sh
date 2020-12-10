#!/bin/bash

# this exposed-command can be used to backup dogu databases stored in postgresql. 

set -o errexit
set -o pipefail

# read service account keys from stdin
while read -r line; do
  case $line in
  username:*)
  username=${line//username: /};;
  database:*)
  database_name=${line//database: /};;
  esac
done

# continue when all service-account keys are provided
if [[ -n $username && -n $database_name ]]; then

  # database dump printed on stdOut
  pg_dump -U "$username" -d "$database_name"

else
  echo "Please provide following service-account keys: username, database" >&2;
  exit 1;
fi

