<h1 align="center">
<code>docker rollout</code><br>
Zero Downtime Deployment for Docker Compose
</h1>

Docker CLI plugin that updates Docker Compose services without downtime.

Simply replace `docker compose up -d <service>` with `docker rollout <service>` in your deployment scripts. This command will scale the service to twice the current number of instances, wait for the new containers to be ready, and then remove the old containers.

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
  - [⚠️ Caveats](#️-caveats)
  - [Sample deployment script](#sample-deployment-script)
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
curl https://raw.githubusercontent.com/wowu/docker-rollout/master/docker-rollout -o ~/.docker/cli-plugins/docker-rollout

# Make the script executable
chmod +x ~/.docker/cli-plugins/docker-rollout
```

## Usage

Run `docker rollout <name>` instead of `docker compose up -d <name>` to update a service without downtime.

```bash
$ docker rollout -f docker-compose.yml <service-name>
```

Options:

- `-f | --file FILE` - (not required) - Path to compose file, can be specified multiple times, as in `docker compose`.
- `-t | --timeout SECONDS` - (not required) - Timeout in seconds to wait for new container to become healthy, if the container has healthcheck defined in `Dockerfile` or `docker-compose.yml`. Default: 60
- `-w | --wait SECONDS` - (not required) - Time to wait for new container to be ready if healthcheck is not defined. Default: 10
- `--env-file FILE` - (not required) - Path to env file, can be specified multiple times, as in `docker compose`.

See examples in [examples](examples) directory for sample `docker-compose.yml` files.

### ⚠️ Caveats

- Your service cannot have `container_name` and `ports` defined in `docker-compose.yml`, as it's not possible to run multiple containers with the same name or port mapping. Use a proxy as described below.
- Proxy like [Traefik](https://github.com/traefik/traefik) or [nginx-proxy](https://github.com/nginx-proxy/nginx-proxy) is required to route traffic.
- Each deployment will increment the index in container name (e.g. `project-web-1` -> `project-web-2`).

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

## Why?

Using `docker compose up` to deploy a new version of a service causes downtime because the app container is stopped before the new container is created.
If your application takes a while to boot, this may be noticeable to users.

Using container orchestration tools like [Kubernetes](https://kubernetes.io/) or [Nomad](https://www.nomadproject.io/) is usually an overkill for projects that will do fine with a single-server Docker Compose setup. [Dokku](https://github.com/dokku/dokku) comes with zero-downtime deployment and more useful features, but it's not as flexible as Docker Compose.

If you have a proxy like [Traefik](https://github.com/traefik/traefik) or [nginx-proxy](https://github.com/nginx-proxy/nginx-proxy), a zero downtime deployment can be achieved by writing a script that scales the service to 2 instances, waits for the new container to be ready, and then removes the old container.
`docker rollout` does exactly that, but with a single command that you can use in your deployment scripts.
If you're using Docker healthchecks, Traefik will make sure that traffic is only routed to the new container when it's ready.

## License

[MIT License](LICENSE) &copy; Karol Musur
