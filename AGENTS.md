# docker-rollout

## What this is

A single POSIX `sh` script, [docker-rollout](docker-rollout), installed as a Docker CLI plugin (`docker rollout <service>`) to do zero-downtime deploys of Docker Compose services. It scales a service to 2× its instances, waits for the new containers to become healthy, then stops and removes them — rolling back if the new containers never become healthy.

The whole program is that one file. No build step, no runtime dependency beyond Docker.

The opt-in built-in HTTP gate runs curl inside one digest-pinned temporary Docker
container. It requires no HTTP client on the host and no permanent component.
Keep the probe image/network/identity contract documented in `docs/cli-options.md`.

## Commands

Tasks are wrapped by the [run](run) script; `./run` lists them.

- **Lint**: `./run lint` (`shellcheck docker-rollout`) — must stay clean; CI runs it on every push/PR.
- **Test**: `./run test` — inits the Bats submodules and runs `bats test/`. **Requires a running Docker daemon.**
- **Run locally**: symlink/copy the script into `~/.docker/cli-plugins/docker-rollout` (executable), then `docker rollout <service>`.
- **Docs site** (Jekyll, in [docs/](docs/)): `cd docs && bundle install && bundle exec jekyll serve`. Deployed to GitHub Pages from `main`.

## Working on the script

- Keep it **POSIX `sh`, not bash** — shebang is `#!/bin/sh`, `set -e` is on, ShellCheck enforces it. No bashisms (arrays, `[[ ]]`, process substitution). No external tools beyond Docker and core POSIX utils — no `jq`, `yq`, `awk`, `python`, or `sed -E`.
- Support both Compose v2 (`docker compose`, preferred) and v1 (`docker-compose`); the script detects which is available.
- Word-splitting is intentional for multi-value options (`$DOCKER_ARGS`, `$COMPOSE_FILES`, `$ENV_FILES`, `$OLD_CONTAINER_IDS`) — preserve the `# shellcheck disable=SC2086` comments on those lines.

### Code style

- Variables: `ALL_CAPS_SNAKE_CASE`.
- User-facing messages prefixed with `==> `; errors go to stderr (`>&2`).
- Quote every expansion in conditionals: `[ -z "$VAR" ]`.
- String work with `tr`/`grep`/`sed`/`cut`/`wc` (basic regex only), not `awk`.

### Structure (top to bottom)

1. **Plugin metadata short-circuit** — if invoked as `docker-cli-plugin-metadata`, print JSON and exit.
2. **Docker arg capture** — args before the literal `rollout` token become `$DOCKER_ARGS`, re-passed to every `docker`/`compose` call.
3. **Compose command detection** — stored in `$COMPOSE_COMMAND`.
4. **`main()`** — the rollout algorithm: record old container IDs, scale to 2×, diff to find new IDs, wait on healthcheck (or a fixed `--wait`), run the pre-stop hook, stop+remove old containers, rolling back on failure.
5. **Option parser** — the `while`/`case` loop fills the globals (`COMPOSE_FILES`, `ENV_FILES`, `HEALTHCHECK_TIMEOUT`, `PRE_STOP_HOOK`, `SERVICE`, …), then `main` runs.

Behaviors to preserve:
- A `--pre-stop-hook` CLI value overrides the `docker-rollout.pre-stop-hook` label; the label is read from the *old* container, so label-based hooks only take effect on the *next* deploy.
- Services can't use `container_name` or fixed host `ports` — two instances must coexist during rollout. This is a documented caveat, not enforced by the script.

## Tests

Real-container integration tests via [Bats](https://github.com/bats-core/bats-core) in [test/rollout.bats](test/rollout.bats). Bats-core and bats-support are pinned git **submodules** under `test/`; a fresh clone needs `git submodule update --init --recursive` (which `./run test` does).

- Fixtures in [test/fixtures/](test/fixtures/) are a tiny `busybox httpd` service. `compose.yml` is the base; `compose.healthcheck.yml` adds a passing healthcheck; `compose.unhealthy.yml` an always-failing one for the rollback path. Tests combine them with multiple `-f` flags.
- Scenarios cover: swap without healthcheck, swap after healthcheck passes, rollback when the new container never gets healthy, and a 2→4→2 roll checking container-ID diffing.
- Invoke the script **with the literal `rollout` token first** (`./docker-rollout rollout -f … web`) — it consumes everything before that token as docker global args. Each test uses its own `COMPOSE_PROJECT_NAME` and is torn down with `docker compose down -v`.

## Docs

User-facing docs in [docs/](docs/) are the source of truth for option semantics and setup guides. When you change script behavior or options, update both [README.md](README.md) and the relevant `docs/` page.
