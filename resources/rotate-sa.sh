#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

if [ $# -lt 2 ]; then
    echo "usage rotate-sa.sh username servicename" >&2
    exit 1
fi

USERNAME="${*: -2:1}"
SERVICE="${*: -1}"


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

# The ALTER USER statement contains the new password in plain text. Postgres has several independent settings which
# write the text of a statement into the server log, each at a different point of its processing. All of them are
# turned off for the one connection that changes the password. PGOPTIONS passes them when the connection is
# established, so they apply before the statement reaches the server, and they expire when psql exits; other
# connections keep logging as configured. Only a superuser may change these settings, which the admin user is.
NO_STATEMENT_LOGGING=(
    # log_statement logs statements as soon as they arrive, before they are executed; with "ddl", "mod" or "all"
    # this includes ALTER USER. "none" turns it off.
    "-c log_statement=none"
    # log_min_duration_statement logs each statement which ran longer than the given number of milliseconds,
    # after it has finished. -1 turns it off.
    "-c log_min_duration_statement=-1"
    # log_min_duration_sample does the same as log_min_duration_statement, but only for a random share of the
    # statements (log_statement_sample_rate). -1 turns it off.
    "-c log_min_duration_sample=-1"
    # log_transaction_sample_rate logs every statement of a random share of the transactions. 0 turns it off.
    "-c log_transaction_sample_rate=0"
    # log_min_error_statement adds the text of a failed statement to its error message, by default from level error.
    # panic is the highest level, which only a crash of the server reaches, so a failed ALTER USER logs the error
    # but not the statement.
    "-c log_min_error_statement=panic"
    # debug_print_parse, debug_print_rewritten and debug_print_plan log the internal trees of each statement for
    # debugging the server; the parse tree contains the password. off turns them off.
    "-c debug_print_parse=off"
    "-c debug_print_rewritten=off"
    "-c debug_print_plan=off"
)

{
    NEW_PASSWORD=$(doguctl random)

    # update password; the statement is passed via stdin so the password does not show up in the process list.
    echo "ALTER USER ${USERNAME} WITH PASSWORD '${NEW_PASSWORD}';" | PGOPTIONS="${NO_STATEMENT_LOGGING[*]}" psql -v ON_ERROR_STOP=1 -U "${ADMIN_USERNAME}"

} >/dev/null 2>&1

echo "password: ${NEW_PASSWORD}"
