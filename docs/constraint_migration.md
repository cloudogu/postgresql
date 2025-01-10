### Migration der vorhanden Constraints in partitionierten Tabellen

In Postgresql 14.14 wurde ein Fehler gefixed, durch den partitionierte Tabellen beim erneuten Zusammenführen korrupt werden könnten.
Im Update auf diese oder eine spätere Version wird automatisch überprüft, ob es partitionierte Tabellen gibt. Falls dies
der Fall ist, muss eine manuelle Migration der Constraints in diesen Tabellen ausgeführt werden.

Weitere Informationen gibt es in den [Release-Notes](https://www.postgresql.org/docs/14/release-14-14.html#:~:text=Fix%20updates%20of,perform%20each%20step.) von Postgresql.

### Migration
1. Per shell auf den docker-container des betroffenen postgres-Dogus verbinden
2. Mit `psql -U postgres` wird eine interaktive Session mit postgres hergestellt
   Achtung: Da in den Datenbanken produktive Daten liegen könnten, sollten hier keine Daten verändert werden.
3. Folgendes SQL-Statement ausführen:
```SQL
SELECT conrelid::pg_catalog.regclass AS "constrained table",
       conname AS constraint,
       confrelid::pg_catalog.regclass AS "references",
       pg_catalog.format('ALTER TABLE %s DROP CONSTRAINT %I;',
                         conrelid::pg_catalog.regclass, conname) AS "drop",
       pg_catalog.format('ALTER TABLE %s ADD CONSTRAINT %I %s;',
                         conrelid::pg_catalog.regclass, conname,
                         pg_catalog.pg_get_constraintdef(oid)) AS "add"
FROM pg_catalog.pg_constraint c
WHERE contype = 'f' AND conparentid = 0 AND
   (SELECT count(*) FROM pg_catalog.pg_constraint c2
    WHERE c2.conparentid = c.oid) <>
   (SELECT count(*) FROM pg_catalog.pg_inherits i
    WHERE (i.inhparent = c.conrelid OR i.inhparent = c.confrelid) AND
      EXISTS (SELECT 1 FROM pg_catalog.pg_partitioned_table
              WHERE partrelid = i.inhparent));
```

Das Ergebnis der Query sollte wie folgt aussehen

```
     constrained table     |            constraint             | references |                         drop                      |                   add
---------------------------+-----------------------------------+------------+---------------------------------------------------+--------------------------------------------------------------
 users                     | pk_users                          | -          | ALTER TABLE users DROP CONSTRAINT pk_users;       | ALTER TABLE users ADD CONSTRAINT pk_users PRIMARY KEY (name);
```
4. ***Datenbanken der Constraints ermitteln***

Für jeden Eintrag in der Tabelle aus Schritt 3 müssen die drop und add queries ausgeführt werden. Dafür muss zuerst
für jeden Eintrag überprüft werden, zu welcher Datenbank die zugehörige Tabelle gehört. Die folgenden Kommandos können 
in der psql shell genutzt werden (siehe Schritt 2). 

`\l` listet alle Datenbanken auf.

`\c <Datenbankname>` verbindet die Session mit der angegebenen Datenbank

`\dt` listet alle Tabellen dieser Datenbank

Achtung: Es ist möglich, dass mehrere Datenbanken mit gleichen Tabellennamen existieren. Die folgende Query listet alle Constraints der 
gegebenen Datenbank. Diese können mit dem Ergebnis der Tabelle aus Schritt 4 verglichen werden.
```SQL
SELECT conname, pg_catalog.pg_get_constraintdef(r.oid, true) as constraint
FROM pg_catalog.pg_constraint r
WHERE r.conrelid in ('<Datenbankname>'::regclass);
```
5. ***Queries ausführen***

Für jeden Eintrag in Schritt 3 muss zuerst die drop-Query und danach die add-Query ausgeführt werden. Dies ist am einfachsten
mit folgendem Befehl möglich.
```shell
psql -U postgres -d <Datenbankname> -c '<drop-Query>' -c '<add-Query>'
```

6. Nachdem alle Queries ausgeführt wurden ist die Migration abgeschlossen.