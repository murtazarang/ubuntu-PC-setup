#!/usr/bin/env bash
# Open WebUI uses its official OpenAI-compatible connection on localhost:8000.
set -Eeuo pipefail
curl -fsS --max-time 10 http://127.0.0.1:8000/v1/models
printf '\nOpen WebUI connection: http://127.0.0.1:8000/v1 (local key placeholder).\n'
