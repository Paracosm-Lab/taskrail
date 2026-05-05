FROM ruby:3.3
ENV LEGACY_DOCKER_TOKEN=docker-layer-FAKE-token
WORKDIR /app
COPY . .
CMD ["ruby", "bin/credential-audit-smoke"]
