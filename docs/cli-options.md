---
title: CLI Options
nav_order: 3
---

# CLI Options
{: .no_toc }

1. TOC
{:toc}


## Docker flags

All docker flags can be used with `docker rollout` normally, like `--context`, `--env`, `--log-level`, etc.

```bash
docker --context my-remote-context rollout <service-name>
```

The plugin flags are described below.

## `-f | --file FILE`

Path to compose file, can be specified multiple times, as in `docker compose`.

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

## `--env-file FILE`

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

