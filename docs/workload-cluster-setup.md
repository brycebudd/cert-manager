# Workload Cluster Setup

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
  --version v1.17.0 \
  --set crds.enabled=true
```

# Create Service Account for Cert-Manager
This service account is the one defined in your vault kubernetes authenication setup step and will be used by cert-manager to authenticate with vault.

```bash
kubectl create serviceaccount vault-auth-sa --namespace cert-manager
```
> **INFO**
>
> The service account is being created in the default namespace because we are creating a ClusterIssuer.
>
> You would need to ensure that the service account and it's corresponding secret are created in the same namespace as the Issuer if you're using a namespace scoped issuer to connect to Vault.
>



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
vault write auth/kubernetes/login jwt="$SA_TOKEN_REVIEWER_JWT" role="cert-issuer-cluster-a"
```

# Create Cert-Manager ClusterIssuer

## Option 1 - Using Token
```bash
kubectl apply -f -<<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer
spec:
  vault:
    server: "http://172.18.0.12:8200"
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
URL: POST http://172.18.0.12:8200/v1/auth/kubernetes/login
Code: 403. Errors:

* permission denied
```

## Option 2 - Using Service Account
```bash
kubectl apply -f -<<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer
spec:
  vault:
    server: "http://172.18.0.12:8200"
    path: "pki_cluster-a/sign/nonprod"
    auth:
      kubernetes:
        mountPath: "/v1/auth/cluster-a"
        role: vault-issuer
        serviceAccountRef:
          name: vault-auth-sa
          audiences:
          - https://kubernetes.default.svc.cluster.local
EOF
```

### Error

```bash
URL: POST http://172.18.0.12:8200/v1/auth/kubernetes/login
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
    name: vault-auth-sa
    namespace: cert-manager
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: vault-issuer-role
EOF
```

* **Note** This did not work and shouldn't matter because the token was created before...I shouldn't need permission to create it. It may be useful for shortlived token...not my use case.
