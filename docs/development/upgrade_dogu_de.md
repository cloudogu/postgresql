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
2. `post-upgrade.sh` initialisiert mit den Funktionen des offiziellen Entrypoints eine neue Datenbank und startet sie temporär.
3. `restore.sh` spielt das Backup ein, danach laufen Passwort-Rotation und Migrationen wie im regulären Fall.
4. Erst ganz am Ende wird `local_state` entfernt, bis dahin wartet `startup.sh`.

Der Restore muss vollständig in `post-upgrade.sh` laufen und nicht beim regulären Start:
Der Dogu-Operator startet den Pod neu, sobald `post-upgrade.sh` beendet ist.
Ein Restore im Start würde dabei abgebrochen und eine halb eingespielte Datenbank hinterlassen.

Bricht ein Lauf ab, bleibt `migration_backup_path` gesetzt und der nächste Aufruf beginnt mit leerem `PGDATA` von vorne.
Ein `flock` verhindert, dass ein erneuter Aufruf des Operators einen noch laufenden Restore stört.

Regulärer Migrationsfall:

1. Wenn kein Restore nötig ist und eine DB bereits initialisiert ist, startet `post-upgrade.sh` PostgreSQL temporär.
2. Das Superuser-Passwort wird einmalig rotiert (siehe unten).
3. Danach werden Migrationsskripte aus `/docker-entrypoint-initdb.d` (aus `resources/migrations`) manuell ausgeführt.
4. PostgreSQL wird wieder gestoppt und `local_state` entfernt.

### Rotation des Superuser-Passworts (`rotateSuperuserPassword`)

Vor `doguctl` v0.12.2 nutzte `doguctl random` Gos `math/rand` statt `crypto/rand`. Betroffene Werte sind nicht erkennbar, deshalb rotiert jede Instanz ohne Marker.

1. Marker `password_rotated` in der Dogu-Config, kein Versionsvergleich.
2. Reihenfolge: Config, dann `ALTER USER`, dann Marker — eine abgebrochene Rotation wird wiederholt.
3. Läuft nach `startPostgresql`, weil `ALTER USER` eine laufende DB braucht. Über den Unix-Socket genügt `trust`, das alte Passwort wird nicht gebraucht.
4. Läuft auch im Restore-Fall, nachdem das Backup eingespielt wurde.

### Startup (`resources/startup.sh`)

`startup.sh` wartet, solange `local_state=upgrading` gesetzt ist.
Bei leerem `PGDATA` (postgresql nicht installiert) setzt `initAdmin` zusätzlich `password_rotated=true`, da ein frisch erzeugtes Passwort sicher ist.
Danach startet es `/usr/local/bin/docker-entrypoint.sh` mit den Dogu-spezifischen Parametern.

Wichtig:
Der offizielle Entrypoint führt Skripte in `/docker-entrypoint-initdb.d` automatisch nur bei einer frischen Initialisierung aus.
Deshalb gibt es im bestehenden Datenbestand den manuellen Aufruf der Skripte in `post-upgrade.sh`.

## Wo kommen neue Migrationsskripte hin?

Neue Migrationsskripte kommen nach `resources/migrations/` und werden im Dockerfile nach `/docker-entrypoint-initdb.d/` kopiert.

Aktuell:

1. `resources/migrations/02-restrictStatVisibility.sh`
2. `resources/migrations/03-migrateConstraintsOnPartitionedTables.sh`

Der Restore (`resources/restore.sh`) ist bewusst kein Migrationsskript, er wird nur von `post-upgrade.sh` aufgerufen.

## Reihenfolge und Konventionen

1. Skripte als `NN-beschreibung.sh` benennen (`01-...`, `02-...`, ...).
2. Skripte idempotent bauen (mehrfaches Ausführen darf nicht schaden).
3. Abschlussmarker in der Dogu-Config setzen (z. B. `restricted_stat_visibility=true`), damit Schritte nur einmal laufen.
4. Immer mit `set -o errexit -o nounset -o pipefail` arbeiten.