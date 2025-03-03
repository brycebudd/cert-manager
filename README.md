# Cert Manager
This document explains how to install cert-manager as a Private CA suitable for issuing workload certificates suitable for MTLS and possibly other security use cases.

### Principles
- Use vault for secret storage over Kubernetes Secrets
- Use cluster specific intermediate CAs for certficiate issuance
```java
Root CA (Offline/Secured)
       ├── Intermediate CA (Stored in Vault)
               ├── cluster A Intermediate CA (Vault PKI Engine)
               ├── cluster B Intermediate CA (Vault PKI Engine)
               ├── cluster C Intermediate CA (Vault PKI Engine)
```
- 
### Questions/Issues
- Research Vault support for Intermediate CA approach
- Research Trust Manager and TLS Bundles as a Container
- Research Cert Rotation

# Certificate Management with Vault PKI

## Install Vault Cluster
```bash
make CLUSTER_NAME=vault cluster
```

## Vault Setup and Install

### Install Vault CLI
```bash
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install vault
```
### Install Vault to Kubernetes
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com

helm repo update

helm install vault hashicorp/vault --set "server.dev.enabled=true"

```

### Vault Login

#### Using Vault CLI on Separate Machine

```bash
kubectl port-forward pod/vault-0 8200:8200

# in a separate terminal execute...
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root' #assumes default dev mode token, otherwise use assigned

vault login
```

#### Directly to Kubernetes Instance
```bash
kubectl exec -it vault-0 -- /bin/sh
vault login $VAULT_DEV_ROOT_TOKEN_ID
```

## Enable the PKI secret engine for the Root CA

```bash
vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki
```

### Generate the Root CA Certificate

```bash
vault write pki/root/generate/internal \
    common_name="RootCA" \
    ttl=87600h
```

### Configure Issuing Certificates and Certificate Revocation Distribution List

```bash
vault write pki/config/urls \
    issuing_certificates="http://vault-internal:8200/v1/pki/ca" \
    crl_distribution_points="http://vault-internal:8200/v1/pki/crl"
```

## Setup Intermediate CA

```bash
vault secrets enable -path=pki_int pki
vault secrets tune -max-lease-ttl=43800h pki_int
```

### Generate Intermediate CA Signing Request

```bash
vault write pki_int/intermediate/generate/internal \
    common_name="IntermediateCA" \
    ttl=43800h

# OR

vault write -format=json pki_int/intermediate/generate/internal \
     common_name="IntermediateCA" \
     | jq -r '.data.csr' > pki_int.csr
```

### Sign the Intermediate CA with the Root Certificate

```bash
vault write pki/root/sign-intermediate \
    csr=@pki_int.csr \
    format=pem_bundle \
    ttl=43800h

# OR

vault write -format=json pki/root/sign-intermediate \
     csr=@pki_int.csr \
     format=pem_bundle ttl="43800h" \
     | jq -r '.data.certificate' > intermediate.pem    
```

### Import the Signed Certificate

```bash
vault write pki_int/intermediate/set-signed \
    certificate=@intermediate.pem    
```

## Create the cluster Specific Intermediate CAs

```bash
vault secrets enable -path=cluster-a-pki pki
vault secrets enable -path=cluster-b-pki pki
```

### Generate the Certificate Signing Request for each cluster

```bash
vault write -format=json cluster-a-pki/intermediate/generate/internal \
    common_name="Cluster-A Intermediate CA" \
    ttl=21900h \
    | jq -r '.data.csr' > cluster-a.csr

vault write -format=json cluster-b-pki/intermediate/generate/internal \
    common_name="Cluster-B Intermediate CA" \
    ttl=21900h \
    | jq -r '.data.csr' > cluster-b.csr    
```

### Sign cluster Specific Intermediate CA with Intermediate CA

```bash
vault write -format=json pki_int/root/sign-intermediate \
    csr=@cluster-a.csr \
    format=pem_bundle \
    ttl=21900h \
    | jq -r '.data.certificate' > cluster-a-intermediate.pem    

vault write -format=json pki_int/root/sign-intermediate \
    csr=@cluster-b.csr \
    format=pem_bundle \
    ttl=21900h \
    | jq -r '.data.certificate' > cluster-b-intermediate.pem    
```

### Import cluster-Specific Intermediate CA Certificates

```bash
vault write cluster-a-pki/intermediate/set-signed \
    certificate=@cluster-a-intermediate.pem

vault write cluster-b-pki/intermediate/set-signed \
    certificate=@cluster-b-intermediate.pem
```

## Configure cluster Specific Certificate Issuance

### Setup Certificate Roles for Workloads

```bash
vault write cluster-a-pki/roles/nonprod \
    allowed_domains="bank.net" \
    allow_subdomains=true \
    max_ttl="72h"

vault write cluster-b-pki/roles/nonprod \
    allowed_domains="bank.net" \
    allow_subdomains=true \
    max_ttl="72h"
```
## Create Cluster A

```bash
make CLUSTER_NAME=cluster-a cluster
```

## Setup and Configure Cert-Manager for Cluster A

### Create a Service Account for Cert-Manager to Connect to Vault

```bash
kubectl create serviceaccount cert-manager-vault --namespace cert-manager

```
*Repeat for each additional cluster.*

# Manual Certificate Managment with Cert-Manager

## Generate Certificates for internals
```bash
make gen-intermediate-cert
make CLUSTER_NAME=cluster-a gen-cluster-intermediate-ca-cert
make CLUSTER_NAME=cluster-b gen-cluster-intermediate-ca-cert
make CLUSTER_NAME=vault gen-cluster-intermediate-ca-cert
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

# Appendix

## Highly Available Vault Kubernetes Resources

> 
> If you are moving to product read the following this guide uses a dev instance of vault.
>
> [Vault on Kubernetes](https://developer.hashicorp.com/vault/docs/platform/k8s)
>
> [Vault Helm Configuration](https://developer.hashicorp.com/vault/docs/platform/k8s/helm/configuration)
>
> [HA Vault Server with TLS](https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-minikube-tls)
>
> [Vault Kubernetes Deployment Guide](https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-raft-deployment-guide)
>
> [Connect to External Vault](https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-external-vault)
>
> [Vault Kubernetes Security Guide](https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-security-concerns)
>
> [Intermediate CA in Kubernetes using Vault with Cert-Manager](https://support.hashicorp.com/hc/en-us/articles/21920341210899-Create-an-Intermediate-CA-in-Kubernetes-using-Vault-as-a-certificate-manager)
>
> [Kubernetes Cert-Manager with Vault](https://developer.hashicorp.com/vault/tutorials/archive/kubernetes-cert-manager)
>
> [Helpful Support Request for Certifiate Rotation](https://github.com/hashicorp/vault/issues/16461)
>
