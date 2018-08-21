#!/bin/bash

# this exposed-command can be used to backup dogu databases stored in postgresql. 

set -o errexit
set -o pipefail

# read service account keys from stdin
while read -r line; do
  case $line in
  username:*)
  username=$(echo $line | sed -e "s/username: //g");;
  database:*)
  database_name=$(echo $line | sed -e "s/database: //g");;
  esac
done

# continue when all service-account keys are provided
if [[ ! -z $username && ! -z $database_name ]]; then

  # database dump printed on stdOut
  echo "backup data for username: $username and database: $database_name"
  exit 1;
  pg_dump -U $username -d $database_name

else
  echo "Please provide following service-account keys: username, database" >&2;
  exit 1;
fi

