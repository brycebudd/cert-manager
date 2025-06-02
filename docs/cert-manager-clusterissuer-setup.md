# Workload Cert-Manager ClusterIssuer Setup

# Create Cluster A

```bash
make CLUSTER_NAME=cluster-a cluster
```

## Make Sure Cluster A Kubernetes API is accessible Externally (for Vault Auth Token Review)

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


# Install Cert-Manager on Cluster A

```bash
helm repo add jetstack https://charts.jetstack.io --force-update

helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true
```

# Setup Vault Issuer Service Account for Istio

```bash
kubectl create namespace istio-system


kubectl apply -f -<<EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-issuer
  namespace: istio-system
---
apiVersion: v1
kind: Secret
metadata:
  name: vault-issuer
  namespace: istio-system
  annotations:
    kubernetes.io/service-account.name: vault-issuer
type: kubernetes.io/service-account-token
EOF
```

# Setup Istio Certificate Issuer

## External Vault Kubernetes Service
```bash
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Service
metadata:
  name: external-vault
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
      - ip: '172.18.0.5'
    ports:
      - port: 8200
EOF
```
## Create Issuer

```bash
kubectl apply -f -<<EOF
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: vault-nonprod-issuer
  namespace: istio-system
spec:
  vault:
    server: "http://external-vault.default:8200"
    path: "pki_cluster-a/sign/nonprod"
    auth:
      kubernetes:
        mountPath: "/v1/auth/cluster-a"
        role: cluster-a-ca
        secretRef:
          name: vault-issuer
          key: token
EOF

kubectl apply -f -<<EOF
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: vault-nonprod-issuer
  namespace: istio-system
spec:
  vault:
    server: "http://external-vault.default:8200"
    path: "pki_cluster-b/sign/nonprod"
    auth:
      kubernetes:
        mountPath: "/v1/auth/cluster-b"
        role: cluster-b-ca
        secretRef:
          name: vault-issuer
          key: token
EOF
```

# Demo
[Cert-Manager Vault Integration](https://screencast.apps.chrome/1-HpnXN5t23TPIQdzq7vIQ9AarKzTe4HP?createdTime=2025-05-19T21%3A56%3A36.994Z)

---
Everything below this line is suspect and needs to be re-evaluated.

# Create Service Account for Cert-Manager
This service account is the one defined in your vault kubernetes authenication setup step and will be used by cert-manager to authenticate with vault.

```bash
kubectl create serviceaccount vault-auth-sa --namespace cert-manager
```

# Create Token for Cert-Manager Service Account

```bash
kubectl apply -f -<<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vault-auth-secret
  namespace: cert-manager
  annotations:
    kubernetes.io/service-account.name: vault-auth-sa
type: kubernetes.io/service-account-token
EOF
```

# Create Role-Binding for Cert-Manager Service Account

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
  name: vault-auth-sa
  namespace: cert-manager
EOF
```

## Test Authentication with Vault

```bash
vault write auth/cluster-a/login jwt="$SA_TOKEN_REVIEWER_JWT" role="vault-issuer"
```

# Create Cert-Manager ClusterIssuer
The cluster issuer uses a kubernetes service to reference the external vault server, see [Appendix A](#external-vault-kubernetes-service).

## Option 1 - Using Token (Not Preferred)
```bash
kubectl apply -f -<<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer
spec:
  vault:
    server: "http://external-vault.default:8200"
    path: "pki_cluster-a/sign/nonprod"
    auth:
      kubernetes:
        mountPath: "/v1/auth/cluster-a"
        role: vault-issuer
        secretRef:
          name: vault-auth-secret
          key: token
EOF
```

### Error
```bash
URL: POST http://external-vault:8200/v1/auth/cluster-a/login
Code: 403. Errors:

* permission denied
```

## Option 2 - Using Service Account (Preferred)
```bash
kubectl apply -f -<<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer
spec:
  vault:
    server: "http://external-vault.default:8200"
    path: "pki_cluster-a/sign/nonprod"
    auth:
      kubernetes:
        mountPath: "/v1/auth/cluster-a"
        role: vault-issuer
        secretRef:
          name: vault-auth-secret
          key: token
EOF
```

### Error

```bash
URL: POST http://external-vault:8200/v1/auth/cluster-a/login
Code: 403. Errors:

* permission denied
  Warning  ErrInitIssuer  25s (x2 over 25s)  cert-manager-clusterissuers  Error initializing issuer: while requesting a Vault token using the Kubernetes auth: while requesting a token for the service account /vault-auth-sa: serviceaccounts "vault-auth-sa" is forbidden: User "system:serviceaccount:cert-manager:cert-manager" cannot create resource "serviceaccounts/token" in API group "" in the namespace "cert-manager"
```

#### Resolution
Create a role and rolebinding to allow the service account permission to create tokens.

```bash
kubectl apply -f -<<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: vault-issuer-role
rules:
  - apiGroups: ['']
    resources: ['serviceaccounts/token']
    resourceNames: ['vault-auth-sa']
    verbs: ['create']
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-issuer-rolebinding
subjects:
  - kind: ServiceAccount
    name: cert-manager
    namespace: cert-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: vault-issuer-role
EOF
```

#### Notes
I believe both of these permissions errors are primarily due to using an incorrect endpoint for the tokenreviewer KUBE_HOST of the workload cluster when configuring vault authentication. 

**Wrong Config**
```bash
vault write auth/cluster-a/config \
    token_reviewer_jwt="$SA_TOKEN_REVIEWER_JWT" \
    kubernetes_host="https://$SA_HOST:443" \ # This was pointing to the Kubernetes LoadBalancer External IP which is not valid dnsName for this ca cert so it fails.
    kubernetes_ca_cert="$SA_CA_CERT"
```

**Correct Config**
```bash
vault write auth/cluster-a/config \
    token_reviewer_jwt="$SA_TOKEN_REVIEWER_JWT" \ #THIS IS THE VAULT-AUTH-SECRET TOKEN
    kubernetes_host="https://$SA_HOST" \ #THIS IS THE ACTUAL API HOST 
    kubernetes_ca_cert="$SA_CA_CERT" \ #THIS IS THE Kubernetes Server CA Cert
    disable_local_ca_jwt="true"
```

See [notes](./vault-kubernetes-authentication.md#option-1---confirmed) in Vault Kubernetes Authentication guide.

# Issue Certificate using Cluster Issuer

```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app-cluster-a-domain-net
  namespace: default
spec:
  secretName: app-cluster-a-domain-net-secret
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
  commonName: app.domain.net 
  dnsNames:
  - app.cluster-a.domain.net
EOF
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
      - ip: '172.18.0.5'
    ports:
      - port: 8200
EOF
```
