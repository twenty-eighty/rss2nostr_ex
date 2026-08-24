# syntax=docker/dockerfile:1

ARG ELIXIR_VERSION=1.20.3
ARG OTP_VERSION=28.1.1
ARG BUILD_DEBIAN_VERSION=bookworm-20260713-slim
ARG RUNTIME_DEBIAN_VERSION=bookworm-slim

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${BUILD_DEBIAN_VERSION} AS builder

RUN apt-get update -y && \
    apt-get install -y build-essential git curl ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/prod.exs config/runtime.exs config/
RUN mix deps.compile

COPY assets assets
COPY priv priv
COPY lib lib
COPY rel rel
COPY package.json package-lock.json priv/
RUN cd priv && npm ci --omit=dev

# app.js is gitignored; bundle LiveView/Phoenix JS into the release.
RUN mix assets.setup && mix assets.deploy

RUN mix release

FROM debian:${RUNTIME_DEBIAN_VERSION} AS runtime

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates curl ffmpeg && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN chown nobody /app

ENV MIX_ENV=prod
ENV HOME=/app

COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/rss2nostr ./

USER nobody

ENV PORT=4000
EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1

ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["start"]
