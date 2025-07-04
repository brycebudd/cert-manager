# Vault Kubernetes Authentication

## Create Service Account and Secret
Create a service account and secret for each kubernetes cluster (cluster-a, etc.) that authenticates with vault.

```bash
kubectl apply -f -<<EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-auth
---
apiVersion: v1
kind: Secret
metadata:
  name: vault-auth
  annotations:
    kubernetes.io/service-account.name: vault-auth
type: kubernetes.io/service-account-token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: role-tokenreview-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
  - kind: ServiceAccount
    name: vault-auth
    namespace: default
EOF
```

# Enable Vault Kubenetes Authentication

```bash
vault auth enable -path=cluster-a kubernetes
vault auth enable -path=cluster-b kubernetes
```

# Configure Vault Kubernetes Authentication
TODO: edit this to create auth/cluster-a  
TODO: explain cluster-to-cluster Kubernetes APIs must be open and available.  

```bash
CTX="kind-cluster-a"
export TOKEN_REVIEW_JWT=$(kubectl --context="${CTX}" get secret vault-auth -o go-template='{{ .data.token }}' | base64 --decode)
export KUBE_CA_CERT=$(kubectl --context="${CTX}" config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 --decode)
# Ideal but, does not work with Kind
#KUBE_HOST=$(kubectl --context="${CTX}" config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.server}')
# Works with kind and cloud-provider-kind
export KUBE_HOST="https://$(kubectl --context="${CTX}" get endpoints -o jsonpath='{.items[].subsets[].addresses[].ip}'):6443"

#export SA_TOKEN_REVIEWER_JWT=$(kubectl get secret/vault-auth-secret -o jsonpath='{.data.token}' -n cert-manager | base64 -d; echo)
#export SA_CA_CERT=$(kubectl get secret/vault-auth-secret -o jsonpath='{.data.ca\.crt}' -n cert-manager | base64 -d; echo)
# see option1 notes.
#export SA_HOST=$(kubectl get svc/kubernetes -o jsonpath='{.status.loadBalancer.ingress[*].ip}')
```

## Option 1 - Confirmed!!
- `kubectl proxy --port 8443 &
- http://localhost:8443/api
- use server address below

```bash
vault write auth/cluster-a/config \
    token_reviewer_jwt="$TOKEN_REVIEW_JWT" \
    kubernetes_host="$KUBE_HOST" \
    kubernetes_ca_cert="$KUBE_CA_CERT"

vault write auth/cluster-b/config \
    token_reviewer_jwt="$TOKEN_REVIEW_JWT" \
    kubernetes_host="$KUBE_HOST" \
    kubernetes_ca_cert="$KUBE_CA_CERT"
```
## Option 2
```bash
vault write auth/cluster-a/config \
    token_reviewer_jwt="$SA_TOKEN_REVIEWER_JWT" \
    kubernetes_host="https://$SA_HOST:6443" \
    kubernetes_ca_cert="$SA_CA_CERT" \
    issuer="https://kubernetes.default.svc.cluster.local"
```

## Option 3
```bash
vault write auth/cluster-a/config \
    kubernetes_host="https://$SA_HOST:6443" \
    kubernetes_ca_cert="$SA_CA_CERT" \
    disable_local_ca_jwt="true"
```

The parameters used in the above command are populated based on the workload cluster (e.g. Cluster A etc.).  
| Parameter | Description |
|:----|:----|
| **token_reviewer_jwt** | This is the token from the cluster Service Account<br>`kubectl get secret/vault-auth-secret -o jsonpath='{.data.token}' -n cert-manager \| base64 -d` |
| **kubernetes_host** | This is the externally addressable Kubernetes Host for cluster<br>`kubectl get svc/kubernetes -o jsonpath='{.status.loadBalancer.ingress[*].ip}'` |
| **kubernetes_ca_cert** | This is the ca cert for cluster service account<br>`kubectl get secret/vault-auth-secret -o jsonpath='{.data.ca\.crt}' -n cert-manager \| base64 -d`<br>*or*<br>`kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \| base64 -d` |
| **issuer** (optional) | This is the cluster KubeAPI Issuer<br> `kubectl get --raw /.well-known/openid-configuration \| jq -r '.issuer'` |

# Configure Kubernetes Authentication Role

## Role for Certificate Issuer
```bash
vault write auth/cluster-a/role/cluster-a-ca \
    bound_service_account_names=vault-issuer \
    bound_service_account_namespaces=* \
    policies=pki_cluster-a \
    ttl=24h


vault write auth/cluster-b/role/cluster-b-ca \
    bound_service_account_names=vault-issuer \
    bound_service_account_namespaces=* \
    policies=pki_cluster-b \
    ttl=24h
```
## Role for Secrets
TODO

```bash
vault write auth/cluster-a/role/vault-secrets \
    bound_service_account_names=* \
    bound_service_account_namespaces=* \
    policies=* \
    ttl=24h
```

| Parameter | Description |
|:---|:---|
| **bound_service_account_names** | comma-delimited list of service accounts |
| **bound_service_account_namespaces** | comma-delimited list of namespaces |
| **audience** (optional) | vault://\<namespace\>\/\<issuer-name\> for issuer type<br>vault://\<cluster-issuer-name\> for cluster issuer<br><br>`kubectl get --raw /.well-known/openid-configuration \| jq -r .issuer` |
| **policies** | comma-delimited list of vault polices which apply |
| **ttl** | token time to live |  

