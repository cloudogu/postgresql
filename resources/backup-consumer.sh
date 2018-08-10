#!/bin/bash

# this exposed-command can be used to backup dogu databases stored in postgresql. 

set -o errexit
set -o pipefail

# continue when all parameters are provided
if [[ ! -z $1 && ! -z $2 ]]; then
  # service account 
  username="$1";
  database_name="$2";
  
  # database dump printed on stdOut
  pg_dump -U $username -d $database_name

else 
  echo "ERROR: please provide following parameters: (1) username, (2) database_name"
fi

