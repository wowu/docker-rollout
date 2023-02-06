# Traefik example

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
