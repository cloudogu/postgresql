#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

FROM_VERSION="${1}"
TO_VERSION="${2}"

# versionXLessOrEqualThanY returns true if X is less than or equal to Y; otherwise false
function versionXLessOrEqualThanY() {
  local sourceVersion="${1}"
  local targetVersion="${2}"

  if [[ "${sourceVersion}" == "${targetVersion}" ]]; then
    echo "upgrade to same version"
    return 0
  fi

  declare -r semVerRegex='([0-9]+)\.([0-9]+)\.([0-9]+)-([0-9]+)'

   sourceMajor=0
   sourceMinor=0
   sourceBugfix=0
   sourceDogu=0
   targetMajor=0
   targetMinor=0
   targetBugfix=0
   targetDogu=0

  if [[ ${sourceVersion} =~ ${semVerRegex} ]]; then
    sourceMajor=${BASH_REMATCH[1]}
    sourceMinor="${BASH_REMATCH[2]}"
    sourceBugfix="${BASH_REMATCH[3]}"
    sourceDogu="${BASH_REMATCH[4]}"
  else
    echo "ERROR: source dogu version ${sourceVersion} does not seem to be a semantic version"
    exit 1
  fi

  if [[ ${targetVersion} =~ ${semVerRegex} ]]; then
    targetMajor=${BASH_REMATCH[1]}
    targetMinor="${BASH_REMATCH[2]}"
    targetBugfix="${BASH_REMATCH[3]}"
    targetDogu="${BASH_REMATCH[4]}"
  else
    echo "ERROR: target dogu version ${targetVersion} does not seem to be a semantic version"
    exit 1
  fi

  if [[ $((sourceMajor)) -lt $((targetMajor)) ]] ; then
    return 0;
  fi
  if [[ $((sourceMajor)) -le $((targetMajor)) && $((sourceMinor)) -lt $((targetMinor)) ]] ; then
    return 0;
  fi
  if [[ $((sourceMajor)) -le $((targetMajor)) && $((sourceMinor)) -le $((targetMinor)) && $((sourceBugfix)) -lt $((targetBugfix)) ]] ; then
    return 0;
  fi
  if [[ $((sourceMajor)) -le $((targetMajor)) && $((sourceMinor)) -le $((targetMinor)) && $((sourceBugfix)) -le $((targetBugfix)) && $((sourceDogu)) -lt $((targetDogu)) ]] ; then
    return 0;
  fi

  return 1
}

if versionXLessOrEqualThanY "0.14.13-1" "0.${TO_VERSION}" ; then
    while ! pg_isready >/dev/null; do
      # Postgres is not ready yet to accept connections
      sleep 0.1
    done
    # https://www.postgresql.org/docs/14/release-14-14.html#:~:text=Fix%20updates%20of,perform%20each%20step.
    QUERY="SELECT conrelid::pg_catalog.regclass AS \"constrained table\",
                                      conname AS constraint,
                                      confrelid::pg_catalog.regclass AS \"references\",
                                      pg_catalog.format('ALTER TABLE %s DROP CONSTRAINT %I;',
                                                        conrelid::pg_catalog.regclass, conname) AS \"drop\",
                                      pg_catalog.format('ALTER TABLE %s ADD CONSTRAINT %I %s;',
                                                        conrelid::pg_catalog.regclass, conname,
                                                        pg_catalog.pg_get_constraintdef(oid)) AS \"add\"
                               FROM pg_catalog.pg_constraint c
                               WHERE contype = 'f' AND conparentid = 0 AND
                                  (SELECT count(*) FROM pg_catalog.pg_constraint c2
                                   WHERE c2.conparentid = c.oid) <>
                                  (SELECT count(*) FROM pg_catalog.pg_inherits i
                                   WHERE (i.inhparent = c.conrelid OR i.inhparent = c.confrelid) AND
                                     EXISTS (SELECT 1 FROM pg_catalog.pg_partitioned_table
                                             WHERE partrelid = i.inhparent));"
    RESULT=$(psql -U postgres -c "${QUERY}" | wc -l)
    if (($RESULT > 4)); then
          echo "Found constraints on partitioned tables while performing the upgrade."
          echo "Due to a bug in PostgresQL this could lead to corrupt data when the partitioned tables are reattached."
          echo "A manual migration of these constraints is needed to avoid this issue."
          echo "See constraint_migration.md for further information."
    fi
fi
