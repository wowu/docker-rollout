---
title: Container Draining
nav_order: 4
---

# True zero-downtime deployment with container draining

If you want to make sure that no requests are lost during deployment, you can use the following setup to implement container draining. It requires adding a healthcheck to your container that will be failing on purpose when performing rollout to make the proxy (Traefik or nginx-proxy) stop sending requests to the old container before it's removed. This allows the old container to finish processing any open requests before it is stopped.

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

   Remember that docker-rollout reads labels from the old container, so **this hook will be executed during the next deployment**. CLI options have higher priority than container labels, so you can use it to override the label value.

   **Important:** make sure the sleep time is longer than the healthcheck `interval` × `retries` + `time to finish processing open requests` (e.g. interval: 10s, retries: 3, additional time of 5s = sleep 35) so the healthcheck has enough time to mark the container as unhealthy.

With this configuration, a rollout process looks like this:

1. New container is started.
2. Docker daemon marks the old container as healthy.
3. Proxy starts sending requests to the new container alongside the old container.
4. We create `/tmp/drain` file in the old container.
5. Docker daemon marks the old container as unhealthy.
6. Proxy stops sending requests to the old container.
7. Old container is removed.

See sample configuration for [Traefik](examples/container-draining.md).
