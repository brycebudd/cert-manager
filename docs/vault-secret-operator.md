# Vault Secret Operator
This guide will focus on setting up vault secret operators which uses hashicorp vault deployed on a separate kubernetes cluster. 

Visit [Vault Cluster Setup](./vault-cluster-setup.md) for information on how to setup vault on it's own Kubernetes cluster.

# Setup Cluster A
```bash
make CLUSTER_NAME=cluster-a cluster
```

# Vault Kubernetes Authentication
```bash
export KBCTL_VAULT_CMD="kubectl --context kind-vault exec -ti pod/vault-0 -n vault -- "

# Get Cluster A API Address
printf -v API_HOST "https://%s:%s" \
$(kubectl get endpoints kubernetes -o jsonpath='{.subsets[].addresses[].ip}') \
$(kubectl get endpoints kubernetes -o jsonpath='{.subsets[].ports[].port}')

# Get Cluster A Certificate
export HOST_CA_CERT=$(kubectl config view --raw --minify --flatten \
-o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)

${KBCTL_VAULT_CMD} vault auth enable -path=cluster-a kubernetes

${KBCTL_VAULT_CMD} vault write auth/cluster-a/config \
    kubernetes_host="$API_HOST" \
    kubernetes_ca_cert="$HOST_CA_CERT" \
    disable_local_ca_jwt="true"  
```

# Vault Secrets Engine Configuration

```bash
${KBCTL_VAULT_CMD} vault secrets enable -path=app-dev kv-v2
```

```bash
# Add TLS certificate secret
${KBCTL_VAULT_CMD} vault kv put app-dev/tls-cert \
    cert="-----BEGIN CERTIFICATE-----\n...cert data...\n-----END CERTIFICATE-----"

# Add password secret
${KBCTL_VAULT_CMD} vault kv put app-dev/credential \
username="some.user" \
password="supersecret"

```

# Create External Vault Service

```bash
kubectl --context kind-cluster-a apply -f charts/external-vault.yaml
```

# Install Vault Secrets Operator

```bash
helm install vault-secrets-operator hashicorp/vault-secrets-operator \
    -n vault-secrets-operator-system \
    --create-namespace \
    --set defaultVaultConnection.enabled="true" \
    --set defaultVaultConnection.address="http://external-vault.default:8200" \
    --set defaultVaultConnection.skipTLSVerify="true"
```

# Create Workload Namespace

```bash
kubectl create ns app-dev
```

# Configure Vault Authentication for Workload Secrets

```bash
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Secret
metadata:
  name: app-default-token
  namespace: app-dev
  annotations:
    kubernetes.io/service-account.name: default
type: kubernetes.io/service-account-token
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
   name: role-tokenreview-binding
   namespace: app-dev
roleRef:
   apiGroup: rbac.authorization.k8s.io
   kind: ClusterRole
   name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: default
  namespace: app-dev
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: vault-auth
  namespace: app-dev
spec:
  method: kubernetes
  mount: cluster-a
  kubernetes:
    role: app-dev-role
    serviceAccount: default
EOF
```

# Configure Policy for Vault Authentication Role
```bash
${KBCTL_VAULT_CMD} vault policy write read-app-dev-secrets - <<EOF
path "app-dev/*" {
  capabilities = ["read"]
}
EOF
```

# Configure Vault Authentication Role and Associate to Policy

```bash
${KBCTL_VAULT_CMD} vault write auth/cluster-a/role/app-dev-role \
    bound_service_account_names=default \
    bound_service_account_namespaces=app-dev \
    policies=read-app-dev-secrets \
    ttl=24h
```

# Configure Vault Static Secret Workload

```bash
kubectl apply -f - <<EOF
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: app-credential-secret
  namespace: app-dev
spec:
  type: kv-v2
  mount: app-dev
  path: credential
  destination:
    name: app-dev-credential
    create: true
  refreshAfter: 30s
  vaultAuthRef: vault-auth
EOF
````

## Verify

```bash
kubectl get secret/app-dev-credential -n app-dev -o jsonpath='{.data.username}' | base64 -d
kubectl get secret/app-dev-credential -n app-dev -o jsonpath='{.data.password}' | base64 -d
```
