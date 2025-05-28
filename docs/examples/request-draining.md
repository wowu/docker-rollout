---
title: Traefik w/ Request Draining
parent: Examples
---

# Request Draining with Traefik

Works with Docker Compose v2.

## Files

`Dockerfile`

```Dockerfile
FROM alpine
# Use alpine image with whoami binary to have shell commands available
COPY --from=traefik/whoami /whoami /whoami
ENTRYPOINT [ "/whoami" ]
EXPOSE 80
```

`compose.yml`

```yml
services:
  whoami:
    build: .
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.whoami.entrypoints=web"
      - "traefik.http.routers.whoami.rule=Host(`example.com`)"
    healthcheck:
      test: "test ! -f /tmp/drain"
      interval: 5s
      retries: 1

  traefik:
    image: traefik:v2.9
    container_name: traefik
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
    ports:
      - "80:80"
      - "8080:8080"
    volumes:
      - "/var/run/docker.sock:/var/run/docker.sock:ro"

```

## Steps

1. Change domain in `compose.yml` to a domain pointing to your server.

2. Start all services

   ```bash
   docker compose up -d
   ```

3. Deploy new version of `whoami` service without downtime

   ```bash
   docker rollout whoami --pre-stop-hook "touch /tmp/drain && sleep 10"
   ```

   New container will be created, then the old container will be marked as unhealthy and removed after 10 seconds. Traefik will stop sending requests to the old container when it becomes unhealthy, allowing it to finish pending requests before being removed.
