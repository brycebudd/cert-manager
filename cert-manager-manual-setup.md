# Manual Certificate Managment with Cert-Manager

## Generate Certificates for internals
```bash
make gen-intermediate-cert
make CLUSTER_NAME=cluster-a gen-cluster-intermediate-ca-cert
make CLUSTER_NAME=cluster-b gen-cluster-intermediate-ca-cert
```

## Store cluster A Intermediate Cert as a Kubernetes Secret

```bash
kubectl create secret tls cluster-a-intermediate-ca \
  --cert=./certs/internalA-intermediate-ca.crt \
  --key=./certs/internalA-intermediate-ca.key \
  --namespace cert-manager
```

## Create internalIssuer

```yaml
apiVersion: cert-manager.io/v1
kind: internalIssuer
metadata:
  name: cluster-a-issuer
spec:
  ca:
    secretName: cluster-a-intermediate-ca
```

## Issue Certificate for Workload

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app-tls-cert
  namespace: default
spec:
  secretName: app-tls-secret
  issuerRef:
    name: cluster-a-issuer
    kind: internalIssuer
  dnsNames:
    - myapp.example.com

```