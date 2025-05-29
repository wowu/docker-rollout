---
title: Getting Started
nav_order: 2
---

# Getting Started
{: .no_toc }

1. TOC
{:toc}

## Install docker rollout

_docker rollout_ is a single bash script that lives in docker cli plugins directory. It does not require any additional dependencies to work. To install _docker rollout_:

1. Create Docker cli plugins directory if it does not exist:

   ```bash
   mkdir -p ~/.docker/cli-plugins
   ```

2. Download the docker rollout script to Docker cli plugins directory:

   ```bash
   curl https://raw.githubusercontent.com/wowu/docker-rollout/master/docker-rollout -o ~/.docker/cli-plugins/docker-rollout
   ```

   You can also download it manually from the [latest release page](https://github.com/wowu/docker-rollout/releases/latest), review the script content, and save it to `~/.docker/cli-plugins/docker-rollout`.

3. Make the plugin executable:

   ```bash
   chmod +x ~/.docker/cli-plugins/docker-rollout
   ```

4. Verify that the plugin is available:

   ```bash
   docker rollout --help
   #=> Usage: docker rollout [OPTIONS] SERVICE
   #=> ...
   ```

## Prepare your service

_docker rollout_ requires a Docker Compose file to work. Traffic to your service must be handled by a reverse proxy with automatic service discovery like [Traefik](https://github.com/traefik/traefik) or [nginx-proxy](https://github.com/nginx-proxy/nginx-proxy). Here is a sample Compose file with Traefik reverse proxy and a service:

```yaml
services:
  my-app:
    image: my-app:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.my-app.entrypoints=web"
      - "traefik.http.routers.my-app.rule=Host(`my-app.example.com`)"

  traefik:
    image: traefik:v2.9
    command:
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
    ports:
      - "80:80"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"
```

{: .warning }
Your service cannot expose any `ports`, use `network_mode: host`, or have a defined `container_name`. These options will prevent _docker rollout_ from starting multiple instances of the same service.

Check out the [Examples](examples) section for more sample Compose files.

## Start all services

Firstly start all services. docker rollout will be used later to update the service.

```bash
docker compose up -d
```

## Deploy your service without downtime

Now after modifying the service (e.g. changing the image, rebuiling the image, changing envionment variables) **instead of** running `docker compose up -d` to update the service without downtime run `docker rollout`:

```bash
docker rollout my-app
```

You can also specify the path to the Compose file with `-f` option, just like with `docker compose`:

```bash
docker rollout -f docker-compose.yml my-app
```


This command will scale the service to two instances, wait for the new container to be ready, and then remove the old container. If you run more that one instance of the service, for example using `docker compose scale` or `replicas` in the Compose file, _docker rollout_ will scale the service to twice the current number of instances.

If your service has a healthcheck defined, _docker rollout_ will wait for the new containers to become healthy before removing the old ones. Reverse proxy like Traefik or nginx-proxy will route traffic to the new container automatically, after it becomes healthy.

See [CLI Options](cli-options) for the list of all available options.

## Deployment script

The recommended way of using *docker rollout* is to put it in your deployment script. For example, here is a sample deployment script for a service that is updated by pulling the latest code from a git repository, building a new image, running database migrations, and deploying the new version:

```bash
# Download latest code
git pull
# Build new app image
docker compose build web
# Run database migrations
docker compose run --rm web rake db:migrate
# Deploy new version
docker rollout web
```

Usually `docker rollout <service-name>` will be a drop-in replacement for `docker compose up -d <service-name>` in your deployment scripts.

## Stoping old containers gracefully

If you want to make sure that no requests are lost during deployment, you can use the [container draining](container-draining) setup. It's slightly more complex, but it allows the old container to finish processing any open requests before it is stopped.
