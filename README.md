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
### Setup Vault Policy for Cluster Workloads

Create a named policy that enables read access to the PKI secrets engine paths.

```bash
vault policy write cluster-a-pki - <<EOF
path "cluster-a-pki/*"                { capabilities = ["read", "list", "create", "update"] }
path "cluster-a-pki/sign/nonprod"    { capabilities = ["create", "update"] }
path "cluster-a-pki/issue/nonprod"   { capabilities = ["create"] }
EOF

vault policy write cluster-b-pki - <<EOF
path "cluster-b-pki/*"                { capabilities = ["read", "list"] }
path "cluster-b-pki/sign/nonprod"    { capabilities = ["create", "update"] }
path "cluster-b-pki/issue/nonprod"   { capabilities = ["create"] }
EOF
```
### Enable Kubernetes Auth
```bash
vault auth enable --path=cluster-a kubernetes

vault write auth/cluster-a/config \
    token_reviewer_jwt="$(kubectl get secret cluster-a-issuer-token -n cert-manager -o jsonpath='{.data.token}' | base64 --decode)" \
    kubernetes_host="$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')" \
    kubernetes_ca_cert="$(kubectl get secret cluster-a-issuer-token -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 --decode)"

# alternative

vault write auth/cluster-a/config \
    kubernetes_host="$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.server}')" \
    kubernetes_ca_cert="$(kubectl get secret cluster-a-issuer-token -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 --decode)" \
    disable_local_ca_jwt=true
```

### Create a Vault Issuer Role

Create an Issuer Role for each Cluster Service Account

```bash
vault write auth/cluster-a/role/cluster-a-issuer \
    bound_service_account_names=cluster-a-issuer \
    bound_service_account_namespaces=* \
    policies=cluster-a-pki \
    ttl=24h
```

## Create Cluster A

```bash
make CLUSTER_NAME=cluster-a cluster
```

## Install Cert-Manager

```bash
helm repo add jetstack https://charts.jetstack.io --force-update

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.17.0 \
  --set crds.enabled=true
```

### Create an opaque token for Vault

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: cert-manager-vault-token
  namespace: cert-manager
data:
  token: cm9vdAo=
EOF
```
Then define the Issuer like so

```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer
spec:
  vault:
    server: http://172.18.0.7:8200
    path: cluster-a-pki/sign/nonprod
    auth:
      tokenSecretRef:
          name: cert-manager-vault-token
          key: token
EOF
```
This works but is insecure because it uses the root token to access.

# Cert-Manager Usage
Now that we have our Vault Issuer in place we can use cert-manager to issue certificates in various ways. 

> **Info**
> cert-manager will store certificates it issues as a kubernetes secret by default.
>

## Cert-Manager CSI-Driver

### Installation

```bash
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade cert-manager-csi-driver jetstack/cert-manager-csi-driver \
  --install \
  --namespace cert-manager \
  --wait
```

### Usage
Add a cert-manager enabled volume to your pod. This example will use our newly minted vault issuer.

```bash
kubectl apply -f charts/pod-cert-test.yaml

kubectl exec -it pod/app -- /bin/sh

$ cd /tls
$tls ls
$tls ca.crt, tls.crt, tls.key
$tls exit

kubectl get certificaterequests

kubectl delete pod/app

kubectl get certificaterequests

<empty response>!!!

```

## Dynamically Issue Certificate from Istio

### Create a new cluster-a vault pki role

```bash
vault write cluster-a-pki/roles/istio-ca \
    allowed_domains=bank.net \
    allow_any_name=true  \
    enforce_hostnames=false \
    require_cn=false \
    allowed_uri_sans="spiffe://*" \
    max_ttl=72h
```
create a corresponding issuer and token for this role.

```bash
# The following are pinned to the istio namespace only
k apply -f charts/istio-ca-vault-token.yaml

k apply -f charts/istio-ca-issuer.yaml

```


### Setup Cert-Manager Istio CSR

```bash
kubectl create ns istio-system
```
Pull values from https://github.com/cert-manager/istio-csr/blob/main/deploy/charts/istio-csr/values.yaml and update per `charts/istio-csr-values.yaml`

```bash
helm upgrade --install -n istio-system cert-manager-istio-csr -f charts/istio-csr-values.yaml jetstack/cert-manager-istio-csr

```

### Setup Istio

Install Istio Base
```bash
helm upgrade --install istio-base -n istio-system istio/base
```

Pull Values from [https://github.com/istio/istio/blob/1.20.0/manifests/charts/istio-control/istio-discovery/values.yaml](https://github.com/istio/istio/blob/1.20.0/manifests/charts/istio-control/istio-discovery/values.yaml) and modify per `charts/istio-discovery-values.yaml`

```bash
helm upgrade --install istiod --values charts/istio-discovery-values.yaml -n istio-system istio/istiod
```

Verify Installation Succeeded

```bash
# should report ready=true
kubectl get certificate istiod -n istio-system

# view contents
kubectl describe certificate istiod -n istio-system
```

TODO: Create Istio Gateway and Virtual Service over some pods that talk

## Read a Vault Secret from Kubernetes Pod




# Vault Kubernetes Authentication

>
> *This is a work in progress.*
>

### Create a Service Account for Cert-Manager to Connect to Vault

```bash
kubectl create serviceaccount cluster-a-issuer --namespace cert-manager
```
### Configure Authentication for Cert-Manager and Vault

#### Create a token for Service Account

```bash
kubectl apply -f -<<EOF
apiVersion: v1
kind: Secret
metadata:
  name: cluster-a-issuer-token
  namespace: cert-manager
  annotations:
    kubernetes.io/service-account.name: cluster-a-issuer
type: kubernetes.io/service-account-token
EOF
```
#### Create a role binding for the Service Account

```bash
kubectl apply -f -<<EOF
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
   name: role-tokenreview-binding
   namespace: cert-manager
roleRef:
   apiGroup: rbac.authorization.k8s.io
   kind: ClusterRole
   name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: cluster-a-issuer
  namespace: cert-manager
EOF
```
*Note*: I could not get this method to work; wouldn't connect error 403: permission denied...see alternative.

### Create Vault Kubernetes Auth for Cluster A
this is only valid is using vault kubernetes auth...work in progress.
```bash
vault auth enable --path=cluster-a kubernetes
```

### Create the Vault Issuer for Certificate Manager
This is only valid if you're using vault kubernetes auth
```bash
kubectl apply -f charts/cluster-a-vault-issuer.yaml
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
> [Vault for Multiple Kubernetes Clusters](https://computingforgeeks.com/how-to-integrate-multiple-kubernetes-clusters-to-vault-server/)
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
> [Build your own Certificate Authority with Vault](https://developer.hashicorp.com/vault/tutorials/pki/pki-engine)
>
> [Multi-Cluster Kubernetes with Cert Manager Vault and Istio](https://medium.com/@espinaladrinaldi/istio-multicluster-with-istio-csr-cert-manager-vault-pki-66c2d58f1c7f)
>
