<div align="center">
<h1>
<code>docker rollout</code><br>
Zero Downtime Deployment for Docker Compose
</h1>

[Documentation](https://docker-rollout.wowu.dev)
</div>


Docker CLI plugin that updates Docker Compose services without downtime.

Simply replace `docker compose up -d <service>` with `docker rollout <service>` in your deployment scripts. This command will scale the service to twice the current number of instances, wait for the new containers to be ready, and then remove the old containers.

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
  - [⚠️ Caveats](#️-caveats)
  - [Sample deployment script](#sample-deployment-script)
  - [Draining old containers](#draining-old-containers)
- [Why?](#why)
- [License](#license)

## Features

- ⏳ Zero downtime deployment for Docker Compose services
- 🐳 Works with Docker Compose and `docker-compose`
- ❤️ Supports Docker healthchecks out of the box

## Installation

```bash
# Create directory for Docker cli plugins
mkdir -p ~/.docker/cli-plugins

# Download docker-rollout script to Docker cli plugins directory
curl https://raw.githubusercontent.com/wowu/docker-rollout/main/docker-rollout -o ~/.docker/cli-plugins/docker-rollout

# Make the script executable
chmod +x ~/.docker/cli-plugins/docker-rollout
```

## Usage

Run `docker rollout <name>` instead of `docker compose up -d <name>` to update a service without downtime. If you have both `docker compose` plugin and `docker-compose` command available, docker-rollout will use `docker compose` by default.

```bash
$ docker rollout -f docker-compose.yml <service-name>
```

Options:

- `-f | --file PATH` - (not required) - Path to compose file, can be specified multiple times, as in `docker compose`.
- `-t | --timeout SECONDS` - (not required) - Timeout in seconds to wait for new container to become healthy, if the container has healthcheck defined in `Dockerfile` or `docker-compose.yml`. Default: 60
- `-w | --wait SECONDS` - (not required) - Time to wait for new container to be ready if healthcheck is not defined. Default: 10
- `--wait-after-healthy SECONDS` - (not required) - Time to wait after new container is healthy before removing old container. Works when healthcheck is defined. Default: 0
- `--env-file PATH` - (not required) - Path to env file, can be specified multiple times, as in `docker compose`.
- `-p | --project-name NAME` - (not required) - Project name, as in `docker compose`.
- `--profile NAME` - (not required) - Specify a profile to enable, as in `docker compose`.
- `--pre-stop-hook CMD` - (not required) - Command to run in the old container before stopping it. Can be used for marking the container as unhealthy to make proxy stop sending requests to it, see [container draining](#draining-old-containers) below.

See [detailed options description](https://docker-rollout.wowu.dev/cli-options) and [compose.yml file examples](https://docker-rollout.wowu.dev/examples/) in docs.

### ⚠️ Caveats

- Your service cannot have `container_name` and `ports` defined in `docker-compose.yml`, as it's not possible to run multiple containers with the same name or port mapping. Use a proxy as described below.
- Proxy like [Traefik](https://github.com/traefik/traefik) or [nginx-proxy](https://github.com/nginx-proxy/nginx-proxy) is required to route traffic.
- Each deployment will increment the number in container name (e.g. `project-web-1` -> `project-web-2`).
- To avoid dropping currently processed requests when stopping the old container, you need to setup [container draining](#draining-old-containers), which requires a slightly more complex setup.

### Sample deployment script

Sample deployment script for `web` service:

```bash
# Download latest code
git pull
# Build new app image
docker compose build web
# Run database migrations
docker compose run --rm web rake db:migrate
# Deploy new version without downtime
docker rollout web
```

### Draining old containers

If you want to make sure that no requests are lost during deployment, you can use the following setup to implement container draining. It requires adding a healthcheck to your container that will be failing on purpose when performing rollout to make the proxy (Traefik or nginx-proxy) stop sending requests to the old container before it's removed.

1. Add additional healthcheck to your container. The check should fail when `/tmp/drain` file is present.

   If your service doesn't have a healthcheck yet:

   ```yml
   services:
     web:
       image: myapp:latest
       healthcheck:
         test: test ! -f /tmp/drain
         interval: 5s
         retries: 1
   ```

   If your service already has a healthcheck (e.g. `curl -f http://localhost:3000/healthcheck`):

   ```yml
   services:
     web:
       image: myapp:latest
       healthcheck:
         test: test ! -f /tmp/drain && curl -f http://localhost:3000/healthcheck
         interval: 5s
         retries: 1
   ```


2. Use the following command to perform a zero-downtime deployment:

   ```bash
   docker rollout web --pre-stop-hook "touch /tmp/drain && sleep 10"
   ```

   or add the following label to your service in `docker-compose.yml`:

   ```yml
   services:
     web:
       image: myapp:latest
       labels:
         docker-rollout.pre-stop-hook: "touch /tmp/drain && sleep 10"
   ```

   Remember that docker-rollout reads labels from the old container, so **this hook will work on the next deployment**. CLI options have higher priority than container labels, so you can use it to override the label value.

   **Important:** make sure the sleep time is longer than the healthcheck `interval` × `retries` + `time to finish processing open requests` (e.g. interval: 10s, retries: 3, additional time of 5s = sleep 35) so the healthcheck has enough time to mark the container as unhealthy.

Read more about [container draining in the docs](https://docker-rollout.wowu.dev/container-draining).

## Why use docker-rollout?

Using `docker compose up` to deploy a new version of your app causes downtime because the app container has to be stopped before the new container is created.
If your application takes a while to boot, this may be noticeable to your users.

Using container orchestration tools like [Kubernetes](https://kubernetes.io/) or [Nomad](https://www.nomadproject.io/) can be an overkill for projects that will do fine with a single-server Docker Compose setup. [Dokku](https://github.com/dokku/dokku) comes with zero-downtime deployment and more useful features, but it's not as flexible as Docker Compose.

If you have a proxy like [Traefik](https://github.com/traefik/traefik) or [nginx-proxy](https://github.com/nginx-proxy/nginx-proxy), a zero downtime deployment can be achieved by writing a script that scales the service to 2 instances, waits for the new container to be ready, and then removes the old container.
`docker rollout` does exactly that, but with a single command that you can use in your deployment scripts.
If you're using Docker healthchecks, Traefik will make sure that traffic is only routed to the new container when it's ready.

## License

[MIT License](LICENSE) &copy; [Karol Musur](https://wowu.dev)
