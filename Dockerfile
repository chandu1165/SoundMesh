# syntax=docker/dockerfile:1

FROM ghcr.io/cirruslabs/flutter:stable AS web-build

WORKDIR /src/auralyze_app
COPY auralyze_app/pubspec.yaml auralyze_app/pubspec.lock ./
RUN flutter pub get
COPY auralyze_app/ ./

ARG AURALYZE_BACKEND_URL=
RUN flutter build web --release --dart-define=AURALYZE_BACKEND_URL=${AURALYZE_BACKEND_URL}

FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV AURALYZE_HOST=0.0.0.0
ENV PORT=8080
ENV AURALYZE_WEB_DIR=/app/web
ENV AI_PROVIDER=local-rules
ENV AURALYZE_STORAGE=sqlite

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY backend/ ./backend/
COPY --from=web-build /src/auralyze_app/build/web ./web

EXPOSE 8080

CMD ["python", "backend/server.py"]
