---
title: Traefik
parent: Examples
---

# Traefik

## Compose file

```yml
services:
  whoami:
    image: traefik/whoami
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.whoami.entrypoints=web"
      - "traefik.http.routers.whoami.rule=Host(`whoami.example.com`)"

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

{: .security }
Mounting the Docker socket is a potential security risk. If the traefik container is compromised, an attacker could gain full control of the host. If you are concerned about this risk, consider using [docker-socket-proxy](https://github.com/Tecnativa/docker-socket-proxy) to access the Docker socket from the traefik container, as shown [here](https://chriswiegman.com/2019/11/protecting-your-docker-socket-with-traefik-2/).

## Steps

1. Change domain in `docker-compose.yml` to a domain pointing to your server

2. Start all services

    ```bash
    docker-compose up -d
    ```

3. Change `whoami` image to, for example, `jwilder/whoami`

4. Deploy new version of `whoami` service without downtime

    ```bash
    docker rollout whoami
    ```
