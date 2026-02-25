#!/bin/bash
set -o errexit
set -o nounset
set -o pipefail

function runMigrateConstraintsOnPartitionedTables() {
    echo "Running migrateConstraintsOnPartitionedTables script..."

    if [[ $(doguctl config --default "false" migrated_database_constraints) == "true" ]] ; then
      echo "migrateConstraintsOnPartitionedTables already set to true, skipping migration step..."
      return 0
    fi

    local postgres_user
    postgres_user=$(doguctl config user)

    # get databases
    local databases
    databases=$(psql -U "${postgres_user}" -d postgres -t -A -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres');")

    for DATABASE_NAME in ${databases}; do
        echo "Checking database: ${DATABASE_NAME}"

        local QUERY="SELECT conrelid::pg_catalog.regclass AS \"constrained table\",
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

        local result
        result=$(psql -U "${postgres_user}" -d "${DATABASE_NAME}" -t -A -F'|' -c "${QUERY}")

        if [[ -n "${result}" ]]; then
            echo "Found problematic constraints in ${DATABASE_NAME}. Migrating..."

            # 4. Zeilenweise Verarbeitung des Ergebnisses
            while IFS='|' read -r table_name constraint_name ref_table drop_cmd add_cmd; do
                echo "Fixing constraint '${constraint_name}' on table '${table_name}'..."

                # Befehle ausführen (Output nach /dev/null, da Echo oben reicht)
                psql -v ON_ERROR_STOP=1 -U "${postgres_user}" -d "${DATABASE_NAME}" -c "${drop_cmd}" > /dev/null
                psql -v ON_ERROR_STOP=1 -U "${postgres_user}" -d "${DATABASE_NAME}" -c "${add_cmd}" > /dev/null
            done <<< "${result}"
        else
            echo "No problematic constraints found in ${DATABASE_NAME}."
        fi
    done

    # Flag setzen, damit es nur einmal läuft
    doguctl config migrated_database_constraints "true"
    echo "Successfully run migrateConstraintsOnPartitionedTables script."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    runMigrateConstraintsOnPartitionedTables "$@"
fi