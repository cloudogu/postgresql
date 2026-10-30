#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

if [ $# -lt 2 ]; then
    echo "usage rotate-sa.sh username servicename" >&2
    exit 1
fi

USERNAME="${@: -2:1}"
SERVICE="${@: -1}"


# the username must have been created by create-sa.sh for this service: <service>_<6 lowercase alphanumerics>
if [[ ! "${USERNAME}" =~ ^${SERVICE}_[a-z0-9]{6}$ ]]; then
    echo "username ${USERNAME} does not belong to service ${SERVICE}" >&2
    exit 1
fi

ADMIN_USERNAME=$(doguctl config user)

USER_EXISTS=$(psql -U "${ADMIN_USERNAME}" -tAc "SELECT 1 FROM pg_roles WHERE rolname='${USERNAME}';")
if [ "${USER_EXISTS}" != "1" ]; then
    echo "user ${USERNAME} does not exist" >&2
    exit 1
fi

{
    NEW_PASSWORD=$(doguctl random)

    # update password; the statement is passed via stdin so the password does not show up in the process list
    echo "ALTER USER ${USERNAME} WITH PASSWORD '${NEW_PASSWORD}';" | psql -v ON_ERROR_STOP=1 -U "${ADMIN_USERNAME}"

} >/dev/null 2>&1

echo "password: ${NEW_PASSWORD}"
