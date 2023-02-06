# `docker rollout` - Zero Downtime Deployment for Docker Compose

Run `docker rollout <name>` instead of `docker compose up -d <name>` to update a service without downtime.

Features:

- ⏳ Zero downtime deployment for Docker Compose services
- 🐳 Works with Docker Compose and docker-compose
- ❤️ Supports Docker healthchecks out of the box

## Why?

Using `docker compose up` to deploy a new version of a service causes downtime because the app container is stopped before the new container is created.
If your application takes a while to boot, this may be noticeable to users.

Using container orchestration tools like [Kubernetes](https://kubernetes.io/) or [Nomad](https://www.nomadproject.io/) is usually an overkill for projects that will do fine with a single-server Docker Compose setup.

If you have a proxy like [Traefik](https://github.com/traefik/traefik) or [nginx-proxy](https://github.com/nginx-proxy/nginx-proxy), a zero downtime deployment can be achieved by writing a script that scales the service to 2 instances, waits for the new container to be ready, and then removes the old container.
`docker rollout` does exactly that, but with a single command that you can use in your deployment scripts.
If you're using Docker healthchecks, Traefik will make sure that traffic is only routed to the new container when it's ready.

[Dokku](https://github.com/dokku/dokku) comes with zero-downtime deployment and much more features, but for some projects it's not as flexible as Docker Compose.

## ⚠️ Caveats

- Currently only services with scale 1 are supported
- Your service cannot have `container_name` and `ports` defined in `docker-compose.yml`, as it's not possible to run multiple containers with the same name or port mapping
- Proxy like Traefik or nginx-proxy is required to route traffic
- Each deployment will increase the number in container name by 1 (e.g. `web-1` -> `web-2`)

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

```bash
$ docker rollout -f docker-compose.yml <service-name>
```

Options:

- `-f | --file FILE` - (not required) - Path to compose file, can be specified multiple times, as in `docker-compose`.
- `-t | --timeout SECONDS` - (not required) - Timeout in seconds to wait for new container to become healthy, if the container has healthcheck defined in `Dockerfile` or `docker-compose.yml`. Default: 60
- `-w | --wait SECONDS` - (not required) - Time to wait for new container to be ready if healthcheck is not defined. Default: 10

Sample deployment script for `web` service:

```bash
# Download latest code
git pull
# Build new image
docker compose build web
# Run migrations
docker compose run web rake db:migrate
# Deploy new version
docker rollout web
```

## License

[MIT License](LICENSE) &copy; Karol Musur
