---
title: Nginx Proxy
parent: Examples
---

# Nginx Proxy

Works with Docker Compose v2.

## Compose file

```yml
services:
  whoami:
    image: jwilder/whoami
    environment:
      - VIRTUAL_HOST=whoami.example.com

  nginx-proxy:
    image: nginxproxy/nginx-proxy
    ports:
      - "80:80"
    volumes:
      - /var/run/docker.sock:/tmp/docker.sock:ro
```

## Steps

1. Change domain in `docker-compose.yml` to a domain pointing to your server

2. Start all services

    ```bash
    docker-compose up -d
    ```

3. Change `whoami` image to, for example, `traefik/whoami`.

4. Deploy a new version of `whoami` service without downtime.

    ```bash
    docker rollout whoami
    ```
