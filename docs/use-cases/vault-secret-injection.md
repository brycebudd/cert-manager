# Use Case Vault Secret Injection

# Vault Secret Injection Configuration
This guide describes how to configure vault secrets engine for storing workload secrets and  certificates.

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

# Install Vault Agent Injector on Cluster
```bash
helm install vault hashicorp/vault \
    --set "injector.externalVaultAddr=http://external-vault:8200" \
    --set "injector.authPath=auth/cluster-a"
```
- `injector.externalVaultAddr` will cause the helm chart to only install the Vault Agent Injector.
- `injector.authPath` will tell the injector to use our cluster-specific kubernetes authentication instead of the default auth/kubernetes.
- `external-vault` is a Kubernetes Service the point to the external vault server ip address for convenience. This is documented in the [appendix](#external-vault-kubernetes-service).

# Create Workload Service Account
```bash
kubectl create sa appid-sa -n default
```

## Create Workload Service Account Secret
```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: appid-token-secret
  namespace: default
  annotations:
    kubernetes.io/service-account.name: appid-sa
type: kubernetes.io/service-account-token
EOF
```

# Deploy Workload with Injected Secrets

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: secret-injection-app
  labels:
    app: secret-injection-app
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "appid"
    vault.hashicorp.com/agent-inject-secret-certificates.txt: "appid/data/component/certificates"
    vault.hashicorp.com/agent-inject-secret-credentials.txt: "appid/data/component/credentials"
spec:
  serviceAccountName: appid-sa
  containers:
    - name: app
      image: busybox
      command: [ "/bin/sh", "-c", "--" ]
      args: [ "while true; do sleep 30; done;" ]      
EOF
```

## Verify Vault Agent Injected
If you run `kubectl get pods -n default` you should see appid-component pod with 2 containers and status=running

## Verify Vault Secrets appear in Pod
```bash
# access the application
kubectl exec -it pod/secret-injection-app -c app -n default -- /bin/sh

# view certificates
$ cat /vault/secrets/certificates.txt

# view credentials
$ cat /vault/secrets/credentials.txt
```

# Next Steps

- [Use Agent Templates to extract data for Workloads](https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-sidecar#apply-a-template-to-the-injected-secrets)
- [Container Storage Interface/Secrets Provider](https://developer.hashicorp.com/vault/tutorials/kubernetes/kubernetes-secret-store-driver) - Not endorsed by Openshift.
- [Vault Secret Operator Configuration](./vault-secret-operator.md)

# Appendix

## External Vault Kubernetes Service
```bash
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: external-vault
  namespace: default
spec:
  ports:
  - protocol: TCP
    port: 8200
---
apiVersion: v1
kind: Endpoints
metadata:
  name: external-vault
subsets:
  - addresses:
      - ip: '172.18.0.13'
    ports:
      - port: 8200
EOF
```

## Configure Vault Service Account Token
The vault helm chart will automatically create a vault service account, but it will not have a token (secret) by default since Kubenetes 1.21, so we have to create it if this account is used.

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vault-token-secret
  annotations:
    kubernetes.io/service-account.name: vault
type: kubernetes.io/service-account-token
EOF
```
