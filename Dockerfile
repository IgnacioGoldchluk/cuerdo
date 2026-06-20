ARG ELIXIR_VERSION=1.20.1
ARG OTP_VERSION=29.0.1
ARG DEBIAN_VERSION=trixie-20260610-slim
ARG BUILDER_IMAGE="docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="alpine:3.24"

FROM ${BUILDER_IMAGE} AS builder

# Install build dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git xz-utils curl \
  && rm -rf /var/lib/apt/lists/*

# Install Zig for Burrito. Separate steps for better caching
RUN curl -fL "https://ziglang.org/download/0.15.2/zig-x86_64-linux-0.15.2.tar.xz" -o /tmp/zig.tar.xz

RUN tar -xf /tmp/zig.tar.xz -C /opt && \
    ln -s /opt/zig-x86_64-linux-0.15.2/zig /usr/local/bin/zig && \
    rm /tmp/zig.tar.xz

# Prepare build dir
WORKDIR /app

# Install hex + rebar
RUN mix local.hex --force && mix local.rebar --force

# set build ENV
ENV MIX_ENV="prod"
ENV BURRITO_TARGET="linux"

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY lib lib

# Compile the CLI
RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE} AS final

WORKDIR "/app"

# Only copy the final release from the build stage
# Do not run as less privileged user for now because the burrito wrapped release
# needs to create a directory the first time
COPY --from=builder --chown=nobody:root /app/burrito_out/cuerdo_linux ./cuerdo
ENTRYPOINT [ "cuerdo" ]
