#!/bin/sh
set -eu

export PGPASSFILE=/tmp/.pgpass
trap 'rm -f "$PGPASSFILE"' EXIT
umask 077
printf '%s:%s:%s:%s:%s\n' "$PGHOST" "$PGPORT" "$PGDATABASE" "$PGUSER" "$(cat /run/secrets/postgres-password)" > "$PGPASSFILE"

psql --set=ON_ERROR_STOP=1 --set=database="$PGDATABASE" <<'SQL'
\set exporter_password `cat /run/secrets/postgres-exporter-password`
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres_exporter') THEN
    CREATE ROLE postgres_exporter LOGIN;
  END IF;
END
$$;

ALTER ROLE postgres_exporter PASSWORD :'exporter_password';
GRANT pg_monitor TO postgres_exporter;
GRANT CONNECT ON DATABASE :"database" TO postgres_exporter;
SQL
