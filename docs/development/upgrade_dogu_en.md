# Upgrade of the PostgreSQL Dogu

When developing the PostgreSQL Dogu further, it must be ensured that existing instances can be upgraded to newer versions.
The upgrade path consists of `pre-upgrade.sh` before the image switch and `post-upgrade.sh` after the image switch.

## General process

During a Dogu upgrade, `pre-upgrade.sh` is executed first in the old container.
After that, the new image is started and `post-upgrade.sh` is executed.
At the same time, `startup.sh` starts the official PostgreSQL entrypoint.

### Pre-upgrade (`resources/pre-upgrade.sh`)

`pre-upgrade.sh` decides whether a full backup is required.
A backup is created, among other things, for major upgrades or layout migrations.

Important points:

1. A full backup using `pg_dumpall` is stored under `/var/lib/postgresql/backup`.
2. The backup path is stored in config under `migration_backup_path`.
3. `local_state=upgrading` is set so that `startup.sh` can wait for a running upgrade.

### Post-upgrade (`resources/post-upgrade.sh`)

`post-upgrade.sh` distinguishes between restore cases and regular migrations.

Restore case:

1. If `migration_backup_path` is set, the target directory is prepared for restore.
2. Then `post-upgrade.sh` exits.
3. The actual restore runs on the next regular startup via `01-restore.sh`.

Regular migration case:

1. If no restore is needed and a DB is already initialized, `post-upgrade.sh` starts PostgreSQL temporarily.
2. Then migration scripts from `/docker-entrypoint-initdb.d` (from `resources/migrations`) are executed manually.
3. PostgreSQL is stopped again and `local_state` is removed.

### Startup (`resources/startup.sh`)

`startup.sh` waits as long as `local_state=upgrading` is set.
After that, it starts `/usr/local/bin/docker-entrypoint.sh` with Dogu-specific parameters.

Important:
The official entrypoint executes scripts in `/docker-entrypoint-initdb.d` automatically only for a fresh initialization.
Therefore, for existing data, scripts are called manually in `post-upgrade.sh`.

## Where should new migration scripts be added?

New migration scripts go into `resources/migrations/` and are copied in the Dockerfile to `/docker-entrypoint-initdb.d/`.

Current scripts:

1. `resources/migrations/01-restore.sh`
2. `resources/migrations/02-restrictStatVisibility.sh`
3. `resources/migrations/03-migrateConstraintsOnPartitionedTables.sh`

## Order and conventions

1. Name scripts as `NN-description.sh` (`01-...`, `02-...`, ...).
2. Keep scripts idempotent (running them multiple times must not cause problems).
3. Set completion markers in Dogu config (for example `restricted_stat_visibility=true`) so steps only run once.
4. Always use `set -o errexit -o nounset -o pipefail`.
