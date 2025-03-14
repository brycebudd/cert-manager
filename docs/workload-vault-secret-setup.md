# Workload Vault Secrets Setup

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
Adding `injector.externalVaultAddr` will cause the helm chart to only install the Vault Agent Injector.

`external-vault` is a Kubernetes Service the point to the external vault server ip address for convenience. This is documented in the [appendix](#external-vault-kubernetes-service).

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
  name: appid-component
  labels:
    app: appid-component
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
kubectl exec -it pod/appid-component -c app -n default -- /bin/sh

# view certificates
$ cat /vault/secrets/certificates.txt

# view credentials
$ cat /vault/secrets/credentials.txt
```

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
