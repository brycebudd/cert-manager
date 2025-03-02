# Cert Manager
This document explains how to install cert-manager as a Private CA suitable for issuing workload certificates suitable for MTLS and possibly other security use cases.

### Principles
- Use vault for secret storage over Kubernetes Secrets
- Use cluster specific intermediate CAs for certficiate issuance
```java
Root CA (Offline/Secured)
       ├── Intermediate CA (Stored in Vault)
               ├── Cluster A Intermediate CA (Vault PKI Engine)
               ├── Cluster B Intermediate CA (Vault PKI Engine)
               ├── Cluster C Intermediate CA (Vault PKI Engine)
```
- 
### Questions/Issues
- Research Vault support for Intermediate CA approach
- Research Trust Manager and TLS Bundles as a Container
- Research Cert Rotation


## Installation
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.0/cert-manager.yaml

## Generate Certificates
make gen-clustera-intermediate-cert

## Store Cluster A Intermediate Cert as a Kubernetes Secret

```bash
kubectl create secret tls cluster-a-intermediate-ca \
  --cert=./certs/clusterA-intermediate-ca.crt \
  --key=./certs/clusterA-intermediate-ca.key \
  --namespace cert-manager
```

## Create ClusterIssuer

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
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
    kind: ClusterIssuer
  dnsNames:
    - myapp.example.com

```