---
title: CLI Options
nav_order: 3
---

# CLI Options
{: .no_toc }

1. TOC
{:toc}


## Docker flags

All docker flags can be used with `docker rollout` as usual, like `--context`, `--env`, `--log-level`, etc.

```bash
docker --context my-remote-context rollout <service-name>
```

The plugin flags are described below. Some of the options can be defined as container labels.

## `-f | --file PATH`

Path to compose file, can be specified multiple times, like in `docker compose`.

**Example**

Single file:

```bash
docker rollout -f docker-compose.yml <service-name>
```

With override file:

```bash
docker rollout -f docker-compose.yml -f docker-compose.override.yml <service-name>
```

## `-t | --timeout SECONDS`

Timeout in seconds to wait for new container to become healthy, if the container has healthcheck defined.

With HTTP verification, the subsequent proxy-readiness phase receives this same
timeout separately; it is not one combined deadline for both phases.

Default: 60

**Example**

Decrease timeout to 30 seconds:

```bash
docker rollout --timeout 30 <service-name>
```

## `-w | --wait SECONDS`

Time to wait for new container to be ready if healthcheck is not defined.

Default: 10

**Example**

Increase wait time to 30 seconds for a service that takes longer to start:

```bash
docker rollout --wait 30 <service-name>
```

## `--wait-after-healthy SECONDS`

Time to wait after new container is healthy before removing old container. Works when a healthcheck is defined. Can be useful if the service healthcheck is not reliable and the service needs some time to stabilize (see [#27](https://github.com/wowu/docker-rollout/issues/27)).

Default: 0

**Example**

Wait 10 seconds after a new container is healthy before terminating the old container:

```bash
docker rollout --wait-after-healthy 10 <service-name>
```

## `--env-file PATH`

Path to env file, can be specified multiple times, like in `docker compose`.

See [Docker Compose documentation](https://docs.docker.com/reference/cli/docker/compose/).

**Example**

Single env file:

```bash
docker rollout --env-file .env <service-name>
```

Multiple env files:

```bash
docker rollout --env-file .env --env-file .env.prod <service-name>
```

## `-p | --project-name NAME`

Project name, as in `docker compose`.

See [Docker Compose documentation](https://docs.docker.com/compose/how-tos/project-name/).

**Example**

```bash
docker rollout --project-name my-project <service-name>
```

## `--profile NAME`

Specify a profile to enable, as in `docker compose`.

See [Docker Compose documentation](https://docs.docker.com/compose/how-tos/profiles/#start-specific-profiles).

**Example**

```bash
docker rollout --profile my-profile <service-name>
```

## `--pre-stop-hook COMMAND`

Label: `docker-rollout.pre-stop-hook`

Command to run in the old container before stopping it. Can be used for marking the container as unhealthy to gracefully finish running requests before deleting the container, see [container draining](container-draining).

**Example**

Deploy a new version of the service and mark the old container as unhealthy before stopping it:

```bash
docker rollout --pre-stop-hook "touch /tmp/drain && sleep 10" <service-name>
```

{: .warning }
This requires the service to have a healthcheck defined in `docker-compose.yml` or `Dockerfile` that will fail if `/tmp/drain` file exists.

## `--pre-drain-url URL`

```sh
docker rollout --pre-drain-url https://app.example/health web
```

Supplying the full health-check URL enables HTTP verification. Without this option,
HTTP verification is disabled and no probe container is started. The response
header defaults to `X-Instance`; use `--pre-drain-header` to override it.
After native Docker HEALTHCHECK succeeds,
the plugin requires repeated successful HTTP observations for **five seconds**
before draining old containers. The existing `--timeout` applies separately to
the Docker-health phase and then the HTTP phase (default 60 seconds). HTTP mode
requires at least 7 seconds to allow the five-second window and timestamp rounding.

A response counts as new-backend evidence only with HTTP 200 and exactly one named
header identifying the actual responding container: its unique Docker `Config.Hostname` or full
64-character Docker ID. A default hostname is normally the short 12-character ID;
arbitrary ID prefixes, release versions and image IDs are not accepted. Hostnames
must be unique across both generations. Header names are case-insensitive.

Each fresh sample must observe **every new replica**. A known old response, or an
HTTP 200 without the selected header, is neutral while collecting them. This
allows migration from legacy instances that do not expose identity. Headerless
responses never count toward readiness or replace an unobserved new replica.
Failed HTTP requests, empty/duplicate/unknown identities and gaps between
successful samples reset the window. Loss of Docker
health aborts the rollout. A single successful response never authorizes drain.

Requests use a fresh `rollout_probe` query value, no-cache headers and a new
connection. The URL must use HTTP/HTTPS without credentials or fragments.
Redirects are not followed and TLS certificate verification stays enabled.

Only Docker and standard shell utilities are needed on the CLI host. The HTTP
client runs in one temporary container using `curlimages/curl` pinned to
`sha256:11e64e28c5f58c8d93ee95fcf22ac055f48b0bc440e0ce7d8013bbb5ad6aa8ac`.
The plugin checks/pulls this image before scaling. The probe is read-only, has no
capabilities, host mounts or Docker socket, and uses `no-new-privileges`.
It is removed before drain and on handled exits; its own maximum lifetime is
300 seconds if the CLI host disappears. No permanent component is installed.

## `--pre-drain-header NAME`

Response header containing the actual container identity. Default: `X-Instance`.
Use this option when the endpoint exposes identity under a different header name.
This option alone does not enable HTTP verification.

## `--pre-drain-probe-network NAME`

Optional Docker network for the temporary HTTP client; default `bridge`. The URL
is contacted from the selected Docker daemon's probe network, also with remote
Docker contexts. `localhost` means the probe container. Select an existing
reachable network, or `host` where supported. The plugin does not create or
modify application/proxy networks or copy host credentials, proxy variables or CA files.

## Failure semantics and limits

Before drain, failed readiness attempts stop/remove only new containers and
preserve the old generation. Cleanup failures are reported. If an old pre-stop
hook fails or new Docker health is lost after drain begins, both generations
remain for operator recovery; retaining an old container does not undo drain.

These are sampled observations, not continuous monitoring or a guarantee of
future proxy behavior. Curl requests are bounded to one second; collection and
window timing round up to whole-second timestamps. Docker inspect/run/exec calls
are not watchdog-bounded, so `--timeout` is approximate. The initial bootstrap
keeps the existing Compose start path after option/image preflight, without an
HTTP gate.
