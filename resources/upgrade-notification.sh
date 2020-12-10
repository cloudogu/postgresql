#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

FROM_VERSION="${1}"
TO_VERSION="${2}"

# print major upgrade notification if TO_VERSION is equal or higher than 12.5-1 and FROM_VERSION is lower than 12.5-1
if [ "12.5-1" == "$(printf "%s\\n12.5-1" "${TO_VERSION}" | sort -n | head -n1)" ] && [ "12.5-1" != "$(printf "%s\\n12.5-1" "${FROM_VERSION}" | sort -n | head -n1)" ]; then
    printf "You are starting a major upgrade of the PostgreSQL dogu (from %s to %s)!\\n" "${FROM_VERSION}" "${TO_VERSION}"
    echo "Please consider a backup before doing so, e.g. via the Backup dogu!"
    echo "During the upgrade process a full database dump will be created."
    echo "Therefore please make sure your harddrive has at least as much free space left as your PostgreSQL database currently occupies!"
fi
