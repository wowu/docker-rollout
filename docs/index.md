---
title: Home
nav_order: 1
---

# docker rollout - Docker CLI plugin for updating Docker Compose services without downtime

Simply replace `docker compose up -d <service>` with `docker rollout <service>` in your deployment scripts to update a service without downtime.
{: .fs-5 .fw-300 }

[Get started](#installation){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View on GitHub](https://github.com/wowu/docker-rollout){: .btn .fs-5 .mb-4 .mb-md-0}

## Features

- ⏳ Zero downtime deployment for Docker Compose services
- 🐳 Works with Docker Compose v2 and `docker-compose` v1 ([What's the difference?](docker_compose_versions))
- ❤️ Supports Docker healthchecks out of the box

## How does it work?

This command will scale the service to twice the current number of instances, wait for the new containers to be ready, and then remove the old containers.

## Why is it useful?

Using `docker compose up` to deploy a new version of a service causes downtime because the app container is stopped before the new container is created. If your application takes a while to boot, this may be noticeable to your users.

## Caveats (⚠️ read before using)

- Your service cannot have `container_name` and `ports` defined in `docker-compose.yml`, as it's not possible to run multiple containers with the same name or port mapping. Use a proxy as described below.
- Proxy like [Traefik](https://github.com/traefik/traefik) or [nginx-proxy](https://github.com/nginx-proxy/nginx-proxy) is required to route traffic to the containers. Refer to the [Examples](examples) for sample compose files.
- Each deployment will increment the index in container name (e.g. `project-web-1` -> `project-web-2`).

## Installation

Quick install:

```bash
# Create directory for Docker cli plugins
mkdir -p ~/.docker/cli-plugins
# Download docker-rollout script to Docker cli plugins directory
curl https://raw.githubusercontent.com/wowu/docker-rollout/master/docker-rollout -o ~/.docker/cli-plugins/docker-rollout
# Make the script executable
chmod +x ~/.docker/cli-plugins/docker-rollout
```

## Usage

Run `docker rollout <name>` instead of `docker compose up -d <name>` to update a service without downtime. If you have both `docker compose` plugin and `docker-compose` command available, docker-rollout will use `docker compose` by default.

```bash
docker rollout -f docker-compose.yml <service-name>
```

You can read read more about the setup in [Getting Started](getting-started), see [available cli options](cli-options), and check out some [examples](examples).

### Sample deployment script

Sample deployment script for `web` service:

```bash
# Download latest code
git pull
# Build new app image
docker compose build web
# Run database migrations
docker compose run web rake db:migrate
# Deploy new version
docker rollout web
```

## Rationale and alternatives

Using `docker compose up` to deploy a new version of a service causes downtime because the app container is stopped before the new container is created.
If your application takes a while to boot, this may be noticeable to users.

Using container orchestration tools like [Kubernetes](https://kubernetes.io/) or [Nomad](https://www.nomadproject.io/) is usually an overkill for projects that will do fine with a single-server Docker Compose setup. [Dokku](https://github.com/dokku/dokku) comes with zero-downtime deployment and more useful features, but it's not as flexible as Docker Compose.

If you have a proxy like [Traefik](https://github.com/traefik/traefik) or [nginx-proxy](https://github.com/nginx-proxy/nginx-proxy), a zero downtime deployment can be achieved by writing a script that scales the service to 2 instances, waits for the new container to be ready, and then removes the old container.
`docker rollout` does exactly that, but with a single command that you can use in your deployment scripts.
If you're using Docker healthchecks, Traefik will make sure that traffic is only routed to the new container when it's ready.

## License

[MIT License](https://github.com/wowu/docker-rollout/blob/main/LICENSE) &copy; Karol Musur

