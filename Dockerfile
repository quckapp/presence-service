# ==============================================================================
# Build Stage
# ==============================================================================
FROM hexpm/elixir:1.15.7-erlang-26.2.1-alpine-3.18.4 AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    git \
    nodejs \
    npm \
    openssl-dev

WORKDIR /app

# Set build environment
ENV MIX_ENV=prod
ENV ERL_FLAGS="+JPperf true"

COPY mix.exs ./
RUN mix local.hex --force && mix local.rebar --force
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy config files
COPY config config

# Copy source code
COPY lib lib
RUN mkdir -p priv

# Compile the application
RUN mix compile

# Build the release
RUN mix release presence_service

# ==============================================================================
# Runtime Stage
# ==============================================================================
FROM alpine:3.18 AS runner

# Install runtime dependencies
RUN apk add --no-cache \
    libstdc++ \
    openssl \
    ncurses-libs \
    libgcc \
    curl \
    bash \
    tini

# Create non-root user for security
RUN addgroup -g 1000 -S presence && \
    adduser -u 1000 -S presence -G presence

WORKDIR /app

# Copy the release from builder stage
COPY --from=builder --chown=presence:presence /app/_build/prod/rel/presence_service ./

# Set environment variables
ENV PHX_SERVER=true
ENV MIX_ENV=prod
ENV RELEASE_NODE=presence_service@127.0.0.1
ENV RELEASE_DISTRIBUTION=name

# Expose ports
# 4000 - HTTP server
# 4369 - EPMD (Erlang Port Mapper Daemon) for distributed Erlang
EXPOSE 4000 4369

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:4000/health || exit 1

# Switch to non-root user
USER presence

# Use tini as init system for proper signal handling
ENTRYPOINT ["/sbin/tini", "--"]

# Start the release
CMD ["bin/presence_service", "start"]
