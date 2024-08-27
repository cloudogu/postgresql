#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

FROM_VERSION="${1}"
TO_VERSION="${2}"
FROM_MAJOR_VERSION=$(echo "${FROM_VERSION}" | cut -d '.' -f1)
TO_MAJOR_VERSION=$(echo "${TO_VERSION}" | cut -d '.' -f1)

# print major upgrade notification if TO_MAJOR_VERSION is higher than FROM_MAJOR_VERSION
if [[ "${TO_MAJOR_VERSION}" -gt "${FROM_MAJOR_VERSION}" ]]; then
    printf "You are starting a major upgrade of the PostgreSQL dogu (from %s to %s)!\\n" "${FROM_VERSION}" "${TO_VERSION}"
    echo "Please consider a backup before doing so, e.g. via the Backup dogu!"
    echo "During the upgrade process a full database dump will be created."
    echo "Therefore please make sure your harddrive has at least as much free space left as your PostgreSQL database currently occupies!"
fi
