# Environment Configuration

This folder contains environment-specific configuration files for the Presence Service.

## Available Environments

| File | Environment | Description |
|------|-------------|-------------|
| `dev.env` | Development | Local development with debug logging |
| `test.env` | Test | Automated testing with isolated databases |
| `staging.env` | Staging | Pre-production environment |
| `prod.env` | Production | Production environment with secrets from vault |
| `docker.env` | Docker | Docker Compose local development |

## Usage

### Local Development

```bash
# Copy dev environment to .env
cp envs/dev.env .env

# Start the service
mix phx.server
```

### Docker Development

```bash
# Use docker.env with docker-compose
docker-compose --env-file envs/docker.env up
```

### Running Tests

```bash
# Set test environment
export $(cat envs/test.env | xargs)
mix test
```

### Production/Staging

For production and staging, use a secrets manager (AWS Secrets Manager, HashiCorp Vault, etc.) and inject environment variables at runtime.

```bash
# Example with envsubst
envsubst < envs/prod.env > .env
```

## Environment Variables

### Required

- `SECRET_KEY_BASE` - Phoenix secret key (min 64 chars)
- `JWT_SECRET` - JWT signing secret (must match auth-service)
- `MONGODB_URL` - MongoDB connection string
- `REDIS_URL` - Redis connection string
- `KAFKA_BROKERS` - Kafka broker addresses

### Optional

- `JAEGER_ENDPOINT` - Distributed tracing endpoint
- `LOG_LEVEL` - Logging level (debug, info, warn, error)
