#!/usr/bin/env bats
#
# Integration tests for docker-rollout. Each test brings up a real busybox
# HTTP service via Compose, runs the working-tree ./docker-rollout against it,
# and asserts on real container state. Every test runs in its own Compose
# project (COMPOSE_PROJECT_NAME) and is torn down afterwards.

setup() {
  load 'test_helper/bats-support/load'

  ROLLOUT="$BATS_TEST_DIRNAME/../docker-rollout"
  BASE="$BATS_TEST_DIRNAME/fixtures/compose.yml"
  HEALTHY="$BATS_TEST_DIRNAME/fixtures/compose.healthcheck.yml"
  UNHEALTHY="$BATS_TEST_DIRNAME/fixtures/compose.unhealthy.yml"

  # Isolate each test in its own Compose project. The script inherits this
  # env var, so its `docker compose` calls target the same project.
  export COMPOSE_PROJECT_NAME="docker-rollout-test-${BATS_TEST_NUMBER}-$$"
}

teardown() {
  if [ -n "${ROLLOUT_PID:-}" ]; then
    kill -TERM "$ROLLOUT_PID" 2>/dev/null || true
    wait "$ROLLOUT_PID" 2>/dev/null || true
  fi
  docker compose -f "$BASE" down -v --remove-orphans >/dev/null 2>&1 || true
}

# --- helpers ----------------------------------------------------------------

# IDs of the currently-running `web` containers, one per line.
container_ids() {
  docker compose -f "$BASE" ps -q web
}

# Number of running `web` containers.
running_count() {
  docker compose -f "$BASE" ps -q web | wc -l | tr -d ' '
}

health_status() {
  docker inspect --format='{{.State.Health.Status}}' "$1"
}

# Fail if any ID in $1 (newline-separated) is still among the running IDs.
assert_none_running() {
  local current
  current="$(container_ids)"
  while read -r id; do
    [ -n "$id" ] || continue
    if echo "$current" | grep -q "$id"; then
      fail "old container $id is still running after rollout"
    fi
  done <<<"$1"
}

# --- tests ------------------------------------------------------------------

@test "swaps the container when the service has no healthcheck" {
  docker compose -f "$BASE" up --detach --scale web=1 web
  local old_id
  old_id="$(container_ids)"

  run "$ROLLOUT" rollout -f "$BASE" -w 1 web
  [ "$status" -eq 0 ] || fail "rollout failed ($status): $output"

  [ "$(running_count)" -eq 1 ] || fail "expected 1 running container, got $(running_count)"
  assert_none_running "$old_id"
}

@test "waits for the new container to be healthy, then swaps" {
  docker compose -f "$BASE" -f "$HEALTHY" up --detach --scale web=1 web
  local old_id
  old_id="$(container_ids)"

  run "$ROLLOUT" rollout -f "$BASE" -f "$HEALTHY" -t 30 web
  [ "$status" -eq 0 ] || fail "rollout failed ($status): $output"

  [ "$(running_count)" -eq 1 ] || fail "expected 1 running container, got $(running_count)"
  assert_none_running "$old_id"
  [ "$(health_status "$(container_ids)")" = "healthy" ] || fail "new container is not healthy"
}

@test "rolls back and keeps the old container when the new one never gets healthy" {
  # Old container has no healthcheck, so it stays running throughout.
  docker compose -f "$BASE" up --detach --scale web=1 web
  local old_id
  old_id="$(container_ids)"

  # New containers get an always-failing healthcheck; short timeout so the
  # poll loop gives up quickly.
  run "$ROLLOUT" rollout -f "$BASE" -f "$UNHEALTHY" -t 5 web
  [ "$status" -ne 0 ] || fail "expected rollout to fail, but it succeeded: $output"

  # The old container must survive and be the only one left.
  [ "$(running_count)" -eq 1 ] || fail "expected 1 running container, got $(running_count)"
  echo "$(container_ids)" | grep -q "$old_id" || fail "old container was removed during rollback"
}

# https://github.com/wowu/docker-rollout/issues/20
@test "replaces an exited old container instead of restarting it" {
  docker compose -f "$BASE" up --detach --scale web=1 web
  local old_id
  old_id="$(container_ids)"
  # Force the container into an Exited state (any exit triggers the bug).
  docker stop "$old_id"

  run "$ROLLOUT" rollout -f "$BASE" -w 1 web
  [ "$status" -eq 0 ] || fail "rollout failed ($status): $output"

  # We expect a fresh container running the current config, not the old one.
  [ "$(running_count)" -eq 1 ] || fail "expected 1 running container, got $(running_count)"
  local new_id
  new_id="$(container_ids)"
  [ "$new_id" != "$old_id" ] || fail "old exited container was restarted instead of replaced"
}

@test "rolls a 2-instance service (2 -> 4 -> 2) swapping both containers" {
  docker compose -f "$BASE" -f "$HEALTHY" up --detach --scale web=2 web
  local old_ids
  old_ids="$(container_ids)"
  [ "$(running_count)" -eq 2 ] || fail "fixture setup expected 2 containers, got $(running_count)"

  run "$ROLLOUT" rollout -f "$BASE" -f "$HEALTHY" -t 30 web
  [ "$status" -eq 0 ] || fail "rollout failed ($status): $output"

  # Back down to 2, and neither original container remains.
  [ "$(running_count)" -eq 2 ] || fail "expected 2 running containers, got $(running_count)"
  assert_none_running "$old_ids"

  # Both survivors are healthy new containers.
  while read -r id; do
    [ -n "$id" ] || continue
    [ "$(health_status "$id")" = "healthy" ] || fail "container $id is not healthy"
  done <<<"$(container_ids)"
}

# HTTP tests use a real proxy with a fixed upstream list. Reloading that list is
# admission: Docker health alone does not make a new backend reachable.
http_compose() {
  docker compose -f "$BASE" -f "$BATS_TEST_DIRNAME/fixtures/compose.http.yml" "$@"
}

http_hostname() {
  docker inspect --format='{{.Config.Hostname}}' "$1"
}

proxy_routes() {
  {
    printf 'worker_processes 1;\nevents {}\nhttp {\n  access_log off;\n  upstream backend {\n'
    while read -r id; do
      [ -n "$id" ] || continue
      printf '    server %s:80;\n' "$(docker inspect --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$id")"
    done <<<"$1"
    printf '  }\n  server { listen 80; location / { proxy_pass http://backend; proxy_next_upstream off; } }\n}\n'
  } > "$HTTP_PROXY_CONFIG"
  if [ "${HTTP_PROXY_STARTED:-0}" -eq 1 ]; then
    http_compose exec -T proxy nginx -s reload
  fi
}

start_http_service() {
  HTTP_REPLICAS="${1:-1}"
  export HTTP_STATE_DIR="$BATS_TEST_TMPDIR/http-state"
  export HTTP_PROXY_CONFIG="$BATS_TEST_TMPDIR/nginx.conf"
  HTTP_NETWORK="${COMPOSE_PROJECT_NAME}_default"
  mkdir -p "$HTTP_STATE_DIR"
  : > "$HTTP_PROXY_CONFIG"
  http_compose up --detach --scale "web=$HTTP_REPLICAS" web
  OLD_IDS="$(container_ids)"
  proxy_routes "$OLD_IDS"
  http_compose up --detach proxy
  HTTP_PROXY_STARTED=1
}

start_http_rollout() {
  "$ROLLOUT" rollout -f "$BASE" -f "$BATS_TEST_DIRNAME/fixtures/compose.http.yml" \
    -t 20 --pre-drain-url http://proxy/cgi-bin/health \
    --pre-drain-probe-network "$HTTP_NETWORK" "$@" web > "$BATS_TEST_TMPDIR/rollout.log" 2>&1 &
  ROLLOUT_PID=$!
}

finish_http_rollout() {
  if wait "$ROLLOUT_PID"; then status=0; else status=$?; fi
  ROLLOUT_PID=
  output="$(cat "$BATS_TEST_TMPDIR/rollout.log")"
}

# Bounded condition polling; sleeps only pace retries, never establish readiness.
wait_until() {
  local attempt
  for attempt in {1..150}; do
    if "$@"; then return 0; fi
    sleep 0.1
  done
  fail "condition did not become true: $*; $(cat "$BATS_TEST_TMPDIR/rollout.log" 2>/dev/null)"
}

new_backends_healthy() {
  NEW_IDS="$(container_ids | grep -Fvx "$OLD_IDS" || true)"
  [ "$(echo "$NEW_IDS" | wc -w | tr -d ' ')" -eq "$HTTP_REPLICAS" ] || return 1
  local id
  while read -r id; do
    [ "$(health_status "$id")" = healthy ] || return 1
  done <<<"$NEW_IDS"
}

backend_unhealthy() {
  [ "$(health_status "$1")" = unhealthy ]
}

gate_reached_old() {
  test -s "$HTTP_STATE_DIR/probes-$(http_hostname "${OLD_IDS%%$'\n'*}")"
}

expect_new_requests() {
  local id
  while read -r id; do
    touch "$HTTP_STATE_DIR/expected-$(http_hostname "$id")"
  done <<<"$NEW_IDS"
}

assert_service_ids() {
  [ "$(container_ids | sort)" = "$(echo "$1" | sort)" ] || fail "unexpected running service containers"
  [ "$(docker compose -f "$BASE" ps -aq web | sort)" = "$(echo "$1" | sort)" ] || fail "unexpected leftover service containers"
}

assert_old_undrained() {
  local id
  while read -r id; do
    docker exec "$id" test ! -f /tmp/drain || fail "old container $id was drained"
    [ ! -e "$HTTP_STATE_DIR/drained-$(http_hostname "$id")" ] || fail "old drain marker exists"
  done <<<"$OLD_IDS"
}

probe_ids() {
  docker ps -aq --filter "network=$HTTP_NETWORK" \
    --filter ancestor=curlimages/curl@sha256:11e64e28c5f58c8d93ee95fcf22ac055f48b0bc440e0ce7d8013bbb5ad6aa8ac
}

assert_http_rollback() {
  [ "$status" -ne 0 ] || fail "rollout unexpectedly succeeded: $output"
  assert_service_ids "$OLD_IDS"
  assert_old_undrained
  [ -z "$(probe_ids)" ] || fail "temporary HTTP probe was not removed"
}

assert_http_success() {
  [ "$status" -eq 0 ] || fail "rollout failed ($status): $output"
  assert_service_ids "$NEW_IDS"
  local id host first last last_observation=0 drained
  while read -r id; do
    host="$(http_hostname "$id")"
    [ -s "$HTTP_STATE_DIR/probes-$host" ] || fail "new backend $id was never reached through HTTP"
    first="$(head -n 1 "$HTTP_STATE_DIR/probes-$host" | cut -d ' ' -f 1)"
    last="$(tail -n 1 "$HTTP_STATE_DIR/probes-$host" | cut -d ' ' -f 1)"
    [ "$((last - first))" -ge 5 ] || fail "backend $id had no complete 5-second observation window"
    [ "$last" -le "$last_observation" ] || last_observation="$last"
  done <<<"$NEW_IDS"
  while read -r id; do
    # The hook also requires every expected backend's request marker before it
    # writes this marker, so a premature drain fails the rollout itself.
    drained="$(cat "$HTTP_STATE_DIR/drained-${id:0:12}")"
    [ "$drained" -ge "$last_observation" ] || fail "old backend drained before the final new observation"
  done <<<"$OLD_IDS"
  [ -z "$(probe_ids)" ] || fail "temporary HTTP probe was not removed"
}

@test "waits for HTTP admission before draining a legacy headerless instance" {
  start_http_service
  docker exec "$OLD_IDS" touch /tmp/legacy
  start_http_rollout
  wait_until new_backends_healthy
  wait_until gate_reached_old
  assert_old_undrained
  expect_new_requests

  # Keep the headerless old backend in rotation alongside the admitted new one.
  proxy_routes "${OLD_IDS}"$'\n'"${NEW_IDS}"
  finish_http_rollout
  assert_http_success
}

@test "refused HTTP admission preserves the exact old undrained instance" {
  start_http_service
  docker exec "$OLD_IDS" touch /tmp/legacy
  start_http_rollout
  wait_until new_backends_healthy
  wait_until gate_reached_old
  assert_old_undrained
  finish_http_rollout
  assert_http_rollback
}

@test "allows overriding the default HTTP instance header" {
  start_http_service
  printf 'X-Backend\n' > "$HTTP_STATE_DIR/header"
  start_http_rollout --pre-drain-header X-Backend
  wait_until new_backends_healthy
  expect_new_requests
  proxy_routes "$NEW_IDS"
  finish_http_rollout
  assert_http_success
}

@test "observes every new replica through HTTP before draining both old ones" {
  start_http_service 2
  start_http_rollout
  wait_until new_backends_healthy
  expect_new_requests
  proxy_routes "$NEW_IDS"
  finish_http_rollout
  assert_http_success
}

@test "one reachable new replica cannot approve a two-instance HTTP rollout" {
  start_http_service 2
  start_http_rollout
  wait_until new_backends_healthy
  proxy_routes "${NEW_IDS%%$'\n'*}"
  finish_http_rollout
  assert_http_rollback
}

@test "transient HTTP readiness cannot satisfy the fixed stability window" {
  start_http_service
  start_http_rollout
  wait_until new_backends_healthy
  proxy_routes "$NEW_IDS"
  wait_until test -s "$HTTP_STATE_DIR/probes-$(http_hostname "$NEW_IDS")"
  proxy_routes "$OLD_IDS"
  finish_http_rollout
  assert_http_rollback
}

@test "Docker health loss during the HTTP gate preserves the old instance" {
  start_http_service
  start_http_rollout
  wait_until new_backends_healthy
  wait_until gate_reached_old
  docker exec "$NEW_IDS" touch /tmp/unhealthy
  finish_http_rollout
  assert_http_rollback
  [[ "$output" == *"lost Docker health"* ]] || fail "HTTP gate did not report health loss: $output"
}

@test "TERM removes the HTTP probe without draining old instances" {
  start_http_service
  start_http_rollout
  wait_until new_backends_healthy
  wait_until gate_reached_old
  [ -n "$(probe_ids)" ] || fail "HTTP probe was not started"
  kill -TERM "$ROLLOUT_PID"
  finish_http_rollout
  [ "$status" -ne 0 ] || fail "terminated rollout succeeded"
  assert_service_ids "${OLD_IDS}"$'\n'"${NEW_IDS}"
  assert_old_undrained
  [ -z "$(probe_ids)" ] || fail "TERM left the temporary HTTP probe behind"
}

@test "a failed drain hook retains both generations for manual recovery" {
  docker compose -f "$BASE" -f "$HEALTHY" up --detach web
  local old_id
  old_id="$(container_ids)"
  run "$ROLLOUT" rollout -f "$BASE" -f "$HEALTHY" -t 30 \
    --pre-stop-hook 'touch /tmp/drain; exit 42' web
  [ "$status" -ne 0 ] || fail "failed hook was ignored"
  [ "$(running_count)" -eq 2 ] || fail "both generations were not preserved"
  docker exec "$old_id" test -f /tmp/drain
  [[ "$output" == *"manual recovery"* ]] || fail "missing manual recovery guidance: $output"
}

@test "health loss after a successful drain hook retains both generations" {
  start_http_service
  start_http_rollout --pre-stop-hook '
    touch /tmp/drain /state/hook-started
    for attempt in $(seq 1 150); do
      test ! -e /state/hook-release || exit 0
      sleep 0.1
    done
    exit 1'
  wait_until new_backends_healthy
  proxy_routes "$NEW_IDS"
  wait_until test -e "$HTTP_STATE_DIR/hook-started"
  docker exec "$NEW_IDS" touch /tmp/unhealthy
  wait_until backend_unhealthy "$NEW_IDS"
  touch "$HTTP_STATE_DIR/hook-release"
  finish_http_rollout

  [ "$status" -ne 0 ] || fail "rollout ignored health loss during drain"
  assert_service_ids "${OLD_IDS}"$'\n'"${NEW_IDS}"
  docker exec "$OLD_IDS" test -f /tmp/drain
  [[ "$output" == *"lost health during drain; keeping both generations"* ]] || fail "missing recovery guidance: $output"
  [ -z "$(probe_ids)" ] || fail "temporary HTTP probe was not removed"
}

@test "invalid HTTP options fail before changing service containers" {
  docker compose -f "$BASE" up --detach web
  local old_id option value
  old_id="$(container_ids)"
  while IFS='|' read -r option value; do
    run "$ROLLOUT" rollout -f "$BASE" --pre-drain-url http://proxy/health \
      --pre-drain-header X-Instance -t 20 "$option" "$value" web
    [ "$status" -ne 0 ] || fail "invalid option was accepted: $option $value"
    assert_service_ids "$old_id"
  done <<'CASES'
--pre-drain-url|file:///etc/passwd
--pre-drain-url|http://user:password@proxy/health
--pre-drain-header|Bad Header
--timeout|6
CASES
}
