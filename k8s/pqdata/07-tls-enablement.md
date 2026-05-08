# PQDP-017 §1.4: QuantumVault + PQ Sign TLS Enablement

rt01/rt02 eSign deploys currently connect to `http://quantumvault.pqdata:8200`
and `http://pq-sign.pqdata:8087` because TLS was disabled during initial
bring-up. OPER_RT19-060 REQ-060 security requirements need HTTPS on both.

The QuantumVault binary already supports TLS via `QV_TLS_ENABLED=true` +
`QV_TLS_CERT_FILE` / `QV_TLS_KEY_FILE` (wired in `main.go` `ListenAndServeTLS`).
PQ Sign does not currently terminate TLS in-process; it relies on an nginx
sidecar for HTTPS on `:8443`.

## Cert-manager approach (recommended)

1. Install cert-manager in the cluster (usually already present on rt19):

   ```bash
   kubectl get pods -n cert-manager
   ```

2. Create a self-signed ClusterIssuer for the internal `.pqdata.svc.cluster.local`
   identity (public TLS is terminated at the ingress/gateway layer, not here):

   ```yaml
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: pqdp-internal-ca
   spec:
     selfSigned: {}
   ```

3. Issue certs for each service:

   ```yaml
   apiVersion: cert-manager.io/v1
   kind: Certificate
   metadata:
     name: quantumvault-tls
     namespace: pqdata
   spec:
     secretName: quantumvault-tls
     issuerRef: { name: pqdp-internal-ca, kind: ClusterIssuer }
     dnsNames:
       - quantumvault.pqdata.svc.cluster.local
       - quantumvault.pqdata
     duration: 2160h  # 90d
     renewBefore: 360h
   ```

4. Mount the secret into the QuantumVault Deployment:

   ```yaml
   volumeMounts:
     - name: tls, mountPath: /etc/quantumvault/tls, readOnly: true
   volumes:
     - name: tls
       secret: { secretName: quantumvault-tls }
   env:
     - name: QV_TLS_ENABLED,   value: "true"
     - name: QV_TLS_CERT_FILE, value: /etc/quantumvault/tls/tls.crt
     - name: QV_TLS_KEY_FILE,  value: /etc/quantumvault/tls/tls.key
   ```

5. Update eSign rt01/rt02 manifests:

   ```yaml
   - name: QUANTUMVAULT_URL
     value: https://quantumvault.pqdata.svc.cluster.local:8200
   ```

   eSign's VaultClient already supports HTTPS — the cert's CA must either be
   trusted system-wide (mount the CA bundle into eSign containers) or the
   client must be configured to skip verification for the internal hostname.
   We prefer the former; add the ClusterIssuer's CA cert to `/etc/ssl/certs`
   via init-container.

## Rollback

rt01/rt02 can be rolled back to `http://` by flipping `QUANTUMVAULT_URL`
and leaving `QV_TLS_ENABLED=false` — no data or schema impact.

## Verification

```bash
# TLS handshake check
kubectl -n pqdata port-forward svc/quantumvault 8200:8200 &
openssl s_client -connect localhost:8200 -servername quantumvault.pqdata.svc.cluster.local -showcerts < /dev/null

# eSign can reach QV over HTTPS
kubectl -n rt01 exec -it deploy/esign-service -- wget -qO- \
  --ca-certificate=/etc/ssl/certs/pqdp-ca.crt \
  https://quantumvault.pqdata.svc.cluster.local:8200/healthz
```
