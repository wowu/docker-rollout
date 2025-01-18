# Copy whoami binary to alpine based image to have shell commands available
FROM alpine
COPY --from=traefik/whoami /whoami /whoami
ENTRYPOINT [ "/whoami" ]
EXPOSE 80
