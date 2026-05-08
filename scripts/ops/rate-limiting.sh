#!/bin/bash
# API Rate Limiting (per-tenant, per-service) — TOPS-034

set -e

REDIS_HOST="redis.rt19.svc.cluster.local"
REDIS_PORT=6379
TENANT_LIMIT_PER_SEC=100
SERVICE_LIMIT_PER_SEC=1000
IP_LIMIT_PER_SEC=500

check_rate_limit() {
  local key=$1
  local limit=$2
  local count=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" INCR "$key")
  
  if [ "$count" -eq 1 ]; then
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" EXPIRE "$key" 1
  fi
  
  if [ "$count" -gt "$limit" ]; then
    echo "429"
    return 1
  fi
  
  echo "200"
  return 0
}

echo "Rate limiting configured"
