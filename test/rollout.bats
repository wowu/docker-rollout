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

  run "$ROLLOUT" rollout -f "$BASE" -f "$HEALTHY" -t 30 --wait-after-healthy 0 web
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

  run "$ROLLOUT" rollout -f "$BASE" -f "$HEALTHY" -t 30 --wait-after-healthy 0 web
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
