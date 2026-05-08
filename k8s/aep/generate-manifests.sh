#!/usr/bin/env bash
# Generates Deployment + Service + PDB manifests for all AEP services.
# Usage: bash generate-manifests.sh
set -uo pipefail

REGISTRY="runtimeaicr.azurecr.io/aep"
OUTDIR="$(cd "$(dirname "$0")/services" && pwd)"
mkdir -p "$OUTDIR"

SERVICES=(
  "kya:8301"
  "cost-control:8302"
  "audit-black-box:8303"
  "pii-shield:8304"
  "observability:8305"
  "fraud-shield:8306"
  "memory-vault:8307"
  "commerce-rails:8308"
  "commerce-protocol:8309"
  "marketplace:8310"
  "developer-hub:8311"
  "contract-manager:8312"
  "procurement-hub:8313"
  "finance-rail:8314"
)

for PAIR in "${SERVICES[@]}"; do
  SVC="${PAIR%%:*}"
  PORT="${PAIR##*:}"
  OUT="$OUTDIR/$SVC.yaml"
  cat > "$OUT" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $SVC
  namespace: aep
  labels:
    app: $SVC
    app.kubernetes.io/part-of: runtimeai-aep
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $SVC
  template:
    metadata:
      labels:
        app: $SVC
    spec:
      containers:
        - name: $SVC
          image: ${REGISTRY}/${SVC}:latest
          ports:
            - containerPort: $PORT
          envFrom:
            - configMapRef:
                name: aep-config
            - secretRef:
                name: aep-secrets
          env:
            - name: PORT
              value: "$PORT"
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
          livenessProbe:
            httpGet:
              path: /healthz
              port: $PORT
            initialDelaySeconds: 10
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /healthz
              port: $PORT
            initialDelaySeconds: 5
            periodSeconds: 10
      imagePullSecrets:
        - name: acr-secret
---
apiVersion: v1
kind: Service
metadata:
  name: $SVC
  namespace: aep
spec:
  selector:
    app: $SVC
  ports:
    - port: $PORT
      targetPort: $PORT
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ${SVC}-pdb
  namespace: aep
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: $SVC
YAML
  echo "  wrote $OUT"
done
echo "Done — ${#SERVICES[@]} service manifests generated in $OUTDIR"
