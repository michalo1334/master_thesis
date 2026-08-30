locals {
  entrypoint_script = <<-EOT
    set -eu
    password_file=/run/secrets/redis-password
    password="$(cat "$password_file")"
    case "$password" in
      '') echo "redis-password must not be empty" >&2; exit 1 ;;
      *[!0-9a-fA-F]*) echo "redis-password must be hexadecimal" >&2; exit 1 ;;
    esac
    [ "$${#password}" -eq 64 ] || { echo "redis-password must be 64 hex characters" >&2; exit 1; }
    umask 077
    printf 'requirepass %s\nsave ""\nappendonly no\n' "$password" > /tmp/redis.conf
    chown redis:redis /tmp/redis.conf
    exec /usr/local/bin/docker-entrypoint.sh redis-server /tmp/redis.conf
  EOT
}
