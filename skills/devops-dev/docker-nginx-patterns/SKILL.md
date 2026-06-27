---
name: docker-nginx-patterns
description: >
  Docker multi-stage builds, compose layout, common Dockerfile
  mistakes. nginx reverse proxy + PHP-FPM location blocks.
  Use when devops-dev writes a Dockerfile, docker-compose, or
  nginx server block for a PHP/Go service.
---

# Docker + nginx patterns (PHP-FPM, Go)

## Dockerfile: PHP (Yii2/Laravel)

```dockerfile
# syntax=docker/dockerfile:1.7
# Stage 1: composer deps
FROM composer:2 AS vendor
WORKDIR /app
COPY composer.json composer.lock ./
RUN composer install --no-dev --no-scripts --no-autoloader

# Stage 2: runtime
FROM php:8.3-fpm-bookworm AS runtime
WORKDIR /app

# System deps + php extensions in one layer
RUN apt-get update && apt-get install -y --no-install-recommends \
      libicu-dev libzip-dev libpq-dev \
    && docker-php-ext-install intl zip pdo_pgsql opcache \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Copy vendor from stage 1, then app code
COPY --from=vendor /app/vendor /app/vendor
COPY . /app
RUN composer dump-autoload --optimize --no-dev

# Run as non-root
RUN useradd -u 1000 -m app && chown -R app:app /app
USER app

EXPOSE 9000
CMD ["php-fpm"]
```

Common mistakes:
- `COPY . .` before `composer install` — invalidates cache on every code change. Copy `composer.json` first.
- `RUN apt-get update && apt-get install` without `&& rm -rf /var/lib/apt/lists/*` — image bloats by ~50MB.
- `composer install` (not `install --no-dev`) in prod — dev dependencies leak into runtime.
- `USER root` left implicit — security hole, breaks Kubernetes `runAsNonRoot`.
- `php-fpm` without `-F` or proper CMD — zombies / silent crashes.

## Dockerfile: Go

```dockerfile
# syntax=docker/dockerfile:1.7
FROM golang:1.23-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/app ./cmd/...

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/app /app
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/app"]
```

Common mistakes:
- Not using `distroless`/`scratch` — `golang:1.23` final image is ~800MB vs ~15MB.
- `CGO_ENABLED=1` default — ties you to glibc, breaks distroless. Disable it.
- `-trimpath` missing — binary contains your local paths (`/home/alex/...`), leaks in stack traces.
- `-ldflags="-s -w"` missing — no symbol strip, debug info bloats binary.

## docker-compose: dev stack

```yaml
services:
  app:
    build: .
    volumes:
      - .:/app  # bind-mount for hot reload
    depends_on:
      db:
        condition: service_healthy
    environment:
      DB_DSN: "postgres://app:secret@db:5432/app"

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_PASSWORD: secret
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app"]
      interval: 5s
      timeout: 3s
      retries: 5

  redis:
    image: redis:7-alpine
    command: ["redis-server", "--save", "60", "1"]

volumes:
  pgdata:
```

Common mistakes:
- No `healthcheck` + `depends_on.condition: service_healthy` — app starts before DB ready, race condition.
- Bind-mount in prod — fine in dev, **never** in prod (overwrites container).
- `image: postgres:latest` — version drift on rebuild. Pin tag.
- Secrets in plain env — use Docker secrets or external vault in prod.

## nginx: PHP-FPM reverse proxy

```nginx
server {
    listen 80;
    server_name example.com;
    root /var/www/app/web;  # Yii2 web/ or Laravel public/
    index index.php;

    # Deny dotfiles
    location ~ /\. { deny all; }

    # Static assets — long cache
    location ~* \.(css|js|png|jpg|svg|woff2?)$ {
        expires 30d;
        access_log off;
        try_files $uri =404;
    }

    # Front controller — Yii2 / Laravel
    location / {
        try_files $uri $uri/ /index.php$is_args$args;
    }

    # PHP-FPM
    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_pass app:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
        # Security: hide PHP version in errors
        fastcgi_hide_header X-Powered-By;
    }

    # Block direct execution of non-public PHP
    location ~ ^/(vendor|config|tests|node_modules)/ {
        deny all;
        return 404;
    }
}
```

Common mistakes:
- Missing `try_files $uri =404` before `fastcgi_pass` — request to `info.php` returns blank but the file is executed. Path-traversal / source disclosure risk.
- Missing `fastcgi_hide_header X-Powered-By` — leaks PHP version to attackers.
- `cgi.fix_pathinfo=1` in php.ini (default!) — `/upload.jpg/nonexistent.php` runs as PHP. Set to `0`.
- Static assets served via PHP-FPM — kills latency. Always serve via nginx directly.
- `allow all` on `/admin` — use `allow 10.0.0.0/8; deny all;` or basic_auth.

## nginx: Go reverse proxy

```nginx
upstream app {
    server app:8080;
    keepalive 32;
}

server {
    listen 80;
    server_name example.com;

    location / {
        proxy_pass http://app;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        # Timeouts — Go servers are usually fast, fail fast
        proxy_connect_timeout 2s;
        proxy_read_timeout 10s;
        proxy_send_timeout 10s;
    }
}
```

Common mistakes:
- Missing `proxy_http_version 1.1` + `Connection ""` — no keepalive, every request opens new TCP.
- `proxy_read_timeout 60s` default — masks a stuck Go handler. Lower it.
- No `client_max_body_size` — large uploads (file uploads, multipart forms) silently fail.
- No gzip — JSON/text responses ship uncompressed.

## Things NOT to do

- Don't run nginx as `root` in container — bind to 8080 instead, use unprivileged user.
- Don't `EXPOSE 22` for SSH into container — debug via `docker exec`, not SSH.
- Don't put `.env` in image — use env_file, secrets, or runtime injection.
- Don't use `:latest` in prod — pin to a tag (`:16-alpine`).
- Don't ignore `docker-compose down -v` in dev — stale volumes hide bugs.