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
  name: app-env-certs-vault-kv
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
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: app-env-credentials-vault-kv
  namespace: default
spec:
  type: kv-v2

  # mount path
  mount: appid

  # path of the secret
  path: component/credentials

  # dest k8s secret
  destination:
    name: app-env-credentials
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
kubectl get secrets/app-env-credentials -o jsonpath='{.data.password}' | base64 -d
```
Delete vault static secret and verify kubernetes secret destroyed.
```bash
kubectl delete vaultstaticsecret app-env-certs-vault-kv app-env-credentials-vault-kv

# check
kubectl get secrets/app-env-tls -o yaml

# YAY secrets "app-env-tls" not found
```

See [appendix](#nginx-with-vault-static-secrets) for how to configure nginx to use vault static secrets as configured above.

# Create Dynamic Secret
TODO

# Create PKI
TODO?

# Appendix

## Resources
- [Vault Secret Operator Tutorial](https://developer.hashicorp.com/vault/tutorials/kubernetes/vault-secrets-operator)
  - [Tutorial Source Code](https://github.com/hashicorp-education/learn-vault-secrets-operator)
- [Vault Secrets Operator Tutorial - Medium](https://medium.com/@yurysavenko/using-vault-secrets-operator-in-kubernetes-afba5ccf44f1)
- [Vault Secret Operator](https://developer.hashicorp.com/vault/docs/platform/k8s/vso) 
- [Vault Secret Operator on OpenShift](https://developer.hashicorp.com/vault/docs/platform/k8s/vso/openshift)

## nginx with vault static secrets

```bash
kubectl apply -f - <<EOF
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: nginx-static-certs-vso
  namespace: default
spec:
  type: kv-v2

  # mount path
  mount: appid

  # path of the secret
  path: component/certificates

  # dest k8s secret
  destination:
    name: tls-secret
    create: true

  # static secret refresh interval
  refreshAfter: 30s

  # Name of the CRD to authenticate to Vault
  vaultAuthRef: app-env-auth
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 443
        volumeMounts:
        - name: tls-secret
          mountPath: /etc/nginx/ssl
          readOnly: true
        - name: config-volume
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: tls-secret
        secret:
          secretName: tls-secret
      - name: config-volume
        configMap:
          name: nginx-config          
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  type: LoadBalancer # or NodePort, ClusterIP, depending on your needs
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 443
    targetPort: 443
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
    server {
        listen 443 ssl;
        server_name nginx.domain.net; # Replace with your domain

        ssl_certificate /etc/nginx/ssl/tls.crt;
        ssl_certificate_key /etc/nginx/ssl/tls.key;

        location / {
            return 200 'Hello, World!\n';
        }
    }
EOF
```

### Verify nginx using TLS
```bash
# Get External IP Address of nginx loadbalancer service
export NGINX_LB_IP=kubectl get service nginx-service -o jsonpath='{.status.loadBalancer.ingress[].ip}'

# Add IP address to hosts file
echo "$(kubectl get service nginx-service -o jsonpath='{.status.loadBalancer.ingress[].ip}')  nginx.domain.net" | sudo tee -a /etc/hosts

# issue request and inspect certificate
curl -kv https://nginx.domain.net
```