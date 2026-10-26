#!/bin/sh
# Busybox CGI keeps evidence in the shared fixture directory, including requests
# to legacy instances which deliberately have no identity response header.
INSTANCE=$(hostname)
HEADER=X-Instance
if [ -f /state/header ]; then HEADER=$(cat /state/header); fi
if [ -n "$QUERY_STRING" ]; then
  printf '%s %s\n' "$(date +%s)" "$QUERY_STRING" >> "/state/probes-$INSTANCE"
fi
if [ -f /tmp/drain ]; then
  printf 'Status: 503 Service Unavailable\r\n'
else
  printf 'Status: 200 OK\r\n'
fi
if [ ! -f /tmp/legacy ]; then
  printf '%s: %s\r\n' "$HEADER" "$INSTANCE"
fi
printf 'Content-Type: text/plain\r\n\r\nok\n'
