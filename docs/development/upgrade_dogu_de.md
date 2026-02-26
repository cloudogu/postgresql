# Upgrade des PostgreSQL-Dogus

Bei der Weiterentwicklung des PostgreSQL-Dogus muss sichergestellt werden, dass bestehende Instanzen auf neue Versionen aktualisiert werden können.
Der Upgrade-Pfad besteht aus dem Skript `pre-upgrade.sh` vor dem Image-Wechsel und `post-upgrade.sh` nach dem Image-Wechsel.

## Allgemeiner Ablauf

Beim Dogu-Upgrade wird zuerst im alten Container `pre-upgrade.sh` ausgeführt.
Danach wird das neue Image gestartet und `post-upgrade.sh` ausgeführt.
Gleichzeitig startet `startup.sh` den offiziellen PostgreSQL-Entrypoint.

### Pre-Upgrade (`resources/pre-upgrade.sh`)

`pre-upgrade.sh` entscheidet, ob ein Full-Backup erforderlich ist.
Ein Backup wird unter anderem bei Major-Upgrades oder bei Layout-Migrationen erzeugt.

Wichtige Punkte:

1. Full-Backup mit `pg_dumpall` wird unter `/var/lib/postgresql/backup` abgelegt.
2. Der Backup-Pfad wird in der Config unter `migration_backup_path` gespeichert.
3. `local_state=upgrading` wird gesetzt, damit `startup.sh` auf ein laufendes Upgrade warten kann.

### Post-Upgrade (`resources/post-upgrade.sh`)

`post-upgrade.sh` unterscheidet zwischen Restore-Fall und regulären Migrationen.

Restore-Fall:

1. Wenn `migration_backup_path` gesetzt ist, wird das Zielverzeichnis für einen Restore vorbereitet.
2. Danach beendet sich `post-upgrade.sh`.
3. Der eigentliche Restore läuft beim nächsten regulären Start über `01-restore.sh`.

Regulärer Migrationsfall:

1. Wenn kein Restore nötig ist und eine DB bereits initialisiert ist, startet `post-upgrade.sh` PostgreSQL temporär.
2. Danach werden Migrationsskripte aus `/docker-entrypoint-initdb.d` (aus `resources/migrations`) manuell ausgeführt.
3. PostgreSQL wird wieder gestoppt und `local_state` entfernt.

### Startup (`resources/startup.sh`)

`startup.sh` wartet, solange `local_state=upgrading` gesetzt ist.
Danach startet es `/usr/local/bin/docker-entrypoint.sh` mit den Dogu-spezifischen Parametern.

Wichtig:
Der offizielle Entrypoint führt Skripte in `/docker-entrypoint-initdb.d` automatisch nur bei einer frischen Initialisierung aus.
Deshalb gibt es im bestehenden Datenbestand den manuellen Aufruf der Skripte in `post-upgrade.sh`.

## Wo kommen neue Migrationsskripte hin?

Neue Migrationsskripte kommen nach `resources/migrations/` und werden im Dockerfile nach `/docker-entrypoint-initdb.d/` kopiert.

Aktuell:

1. `resources/migrations/01-restore.sh`
2. `resources/migrations/02-restrictStatVisibility.sh`
3. `resources/migrations/03-migrateConstraintsOnPartitionedTables.sh`

## Reihenfolge und Konventionen

1. Skripte als `NN-beschreibung.sh` benennen (`01-...`, `02-...`, ...).
2. Skripte idempotent bauen (mehrfaches Ausführen darf nicht schaden).
3. Abschlussmarker in der Dogu-Config setzen (z. B. `restricted_stat_visibility=true`), damit Schritte nur einmal laufen.
4. Immer mit `set -o errexit -o nounset -o pipefail` arbeiten.