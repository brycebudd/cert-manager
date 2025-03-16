# Vault Secret Operator Setup
This guide extends the previous setup with Vault Secrets Operator. It presumes the following previous setup guides have been completed. 

1. [Vault Cluster Setup](../vault-cluster-setup.md)
1. [Vault Secret Configuration](../vault-secret-configuration.md)
1. [Vault Kubernetes Authentication](../vault-kubernetes-authentication.md)

# Configure Vault Transit Secrets
TODO: Explain why needed

## Enable Transit Secrets Engine
```bash
vault secrets enable -path=cluster-a-transit transit
```

## Create Encryption Key
```bash
vault write -force cluster-a-transit/keys/vso-client-cache
```

## Create Access Policy for the Vault Secrets Operator Role
```bash
vault policy write cluster-a-auth-policy-operator - <<EOF
path "cluster-a-transit/encrypt/vso-client-cache" {
   capabilities = ["create", "update"]
}
path "cluster-a-transit/decrypt/vso-client-cache" {
   capabilities = ["create", "update"]
}
EOF
```

## Create a Kubernetes Auth Role for Vault Secrets Operator
```bash
vault write auth/cluster-a/role/auth-role-operator \
   bound_service_account_names=vault-secrets-operator-controller-manager \
   bound_service_account_namespaces=vault-secrets-operator-system \
   token_ttl=0 \
   token_period=120 \
   token_policies=cluster-a-auth-policy-operator \
   audience=vault
```

# Create Cluster A

```bash
make CLUSTER_NAME=cluster-a cluster
```

## Make Sure Cluster A Kubernetes API is accessible Externally

```bash
kubectl config use-context kind-cluster-a
kubectl get services #external ip should have a value if not continue

kubectl edit services/kubernetes

# Change spec.type from ClusterIP to LoadBalancer
# Save and exit
```

> **INFO**
>
> Kubernetes Cluster requires a Cloud LoadBalanacer (or cloud-provider-kind) to be running for this to work
>

# Configure Vault Secrets Operator Installation Values
```bash
cat > vault-operator-values.yaml <<EOF
defaultVaultConnection:
  enabled: true
  address: "http://external-vault.default:8200"
  skipTLSVerify: true
controller:
  manager:
    clientCache:
      persistenceModel: direct-encrypted
      storageEncryption:
        enabled: true
        mount: cluster-a
        keyName: vso-client-cache
        transitMount: cluster-a-transit
        kubernetes:
          role: auth-role-operator
          serviceAccount: vault-secrets-operator-controller-manager
          tokenAudiences: ["vault"]
EOF
```
> **INFO**  
> - [Vault Secrets Operator Values](https://github.com/hashicorp/vault-secrets-operator/blob/main/chart/values.yaml)  

# Install Vault Secrets Operator
```bash
helm install vault-secrets-operator hashicorp/vault-secrets-operator -n vault-secrets-operator-system --create-namespace --values vault-operator-values.yaml
```

# Create a Static Secret
explain


## Configure Kubernetes Authentication for Secret
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  # SA bound to the VSO namespace for transit engine auth
  namespace: vault-secrets-operator-system
  name: vso-operator
---
apiVersion: v1
kind: ServiceAccount
metadata:
  namespace: default
  name: appid-sa
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: app-env-auth
  namespace: default
spec:
  method: kubernetes
  mount: cluster-a
  kubernetes:
    role: appid
    serviceAccount: appid-sa
    audiences:
      - vault
EOF
```

## Create Vault Static Secret Resource
```bash
kubectl apply -f - <<EOF
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: vault-kv-app-env
  namespace: default
spec:
  type: kv-v2

  # mount path
  mount: appid

  # path of the secret
  path: component/certificates

  # dest k8s secret
  destination:
    name: app-env-tls
    create: true

  # static secret refresh interval
  refreshAfter: 30s

  # Name of the CRD to authenticate to Vault
  vaultAuthRef: app-env-auth
EOF
  ```

### Verify Secret Pulled
```bash
kubectl get secrets/app-env-tls -o yaml
```
Delete vault static secret and verify kubernetes secret destroyed.
```bash
kubectl delete vaultstaticsecret vault-kv-app-env

# check
kubectl get secrets/app-env-tls -o yaml

# YAY secrets "app-env-tls" not found
```

# Create Dynamic Secret
explain




# Appendix

## Resources
- [Vault Secret Operator Tutorial](https://developer.hashicorp.com/vault/tutorials/kubernetes/vault-secrets-operator)
  - [Tutorial Source Code](https://github.com/hashicorp-education/learn-vault-secrets-operator)
- [Vault Secret Operator](https://developer.hashicorp.com/vault/docs/platform/k8s/vso) 
- [Vault Secret Operator on OpenShift](https://developer.hashicorp.com/vault/docs/platform/k8s/vso/openshift)