#!/bin/bash
# Performance Profiling (CPU, memory, I/O) — TOPS-043

set -e

SERVICE=$1
DURATION=${2:-60}

if [ -z "$SERVICE" ]; then
  echo "Usage: $0 <service-name> [duration-seconds]"
  exit 1
fi

echo "Profiling $SERVICE for $DURATION seconds..."

# CPU profiling (pprof)
kubectl port-forward -n rt19 deployment/$SERVICE 6060:6060 &
sleep 2
curl -s http://localhost:6060/debug/pprof/profile?seconds=$DURATION > /tmp/$SERVICE-cpu-profile.prof

# Memory profiling
curl -s http://localhost:6060/debug/pprof/heap > /tmp/$SERVICE-mem-profile.prof

# Goroutine analysis
curl -s http://localhost:6060/debug/pprof/goroutine > /tmp/$SERVICE-goroutines.txt

echo "Profiling complete:"
echo "  CPU: /tmp/$SERVICE-cpu-profile.prof"
echo "  Memory: /tmp/$SERVICE-mem-profile.prof"
echo "  Goroutines: /tmp/$SERVICE-goroutines.txt"
