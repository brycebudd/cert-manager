# Certificate Manager

## Installation
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.17.0/cert-manager.yaml

```

Setup istio injection on cert-manager namespace
```bash
kubectl label namespace cert-manager istio-injection=enabled
```

Create tests certificates with cert-manager by executing
```bash
kubectl apply -f charts/test-certs.yaml
```

Verify Cert
```bash
kubectl describe certificate -n cert-manager-test
```
## Issuers
Both vault (if configured as a certificate signer) and Venafi can be configured as an Issuer from Cert Manager.

According to the documentation Venafi is easier (and probably the best solution) to configure and setup as an issuer and can be used as a cluster or namespace issuer via cert-manager.

### References
- https://cert-manager.io/docs/configuration/venafi/ 
- https://cert-manager.io/docs/configuration/vault/

## Configuration

### Vault as a Certificate Issuer
Followed this tutorial https://developer.hashicorp.com/vault/tutorials/archive/kubernetes-cert-manager

#### Initial Setup
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com

helm repo update

helm install vault hashicorp/vault --set "injector.enabled=false"
```

Verify with `kubectl get pods` and `kubectl get service`. Note: default namespace assumed.

**Unseal Vault**
```bash
kubectl exec vault-0 -- vault operator init -key-shares=1 -key-threshold=1 \
      -format=json > init-keys.json
```

**Set root token to ENV variable**
```bash
VAULT_UNSEAL_KEY=$(cat init-keys.json | jq -r ".unseal_keys_b64[]")

kubectl exec vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY
```

**Set root token**
```bash
cat init-keys.json | jq -r ".root_token"

VAULT_ROOT_TOKEN=$(cat init-keys.json | jq -r ".root_token")

kubectl exec vault-0 -- vault login $VAULT_ROOT_TOKEN
```

#### Configure PKI Secret Engine
Start shell and configure engine.

```bash
kubectl exec --stdin=true --tty=true vault-0 -- /bin/sh

vault secrets enable pki

vault secrets tune -max-lease-ttl=8760h pki

```

#### Generate Certificate
```bash
vault write pki/root/generate/internal \
    common_name=example.com \
    ttl=8760h

# Configure the PKI secrets engine certificate issuing and certificate revocation list (CRL) endpoints to use the Vault service in the default namespace
vault write pki/config/urls \
    issuing_certificates="http://vault.default:8200/v1/pki/ca" \
    crl_distribution_points="http://vault.default:8200/v1/pki/crl"    
```
Configure a role named example-dot-com that enables the creation of certificates example.com domain with any subdomains.
```bash
vault write pki/roles/example-dot-com \
    allowed_domains=example.com \
    allow_subdomains=true \
    max_ttl=72h
```
Create a policy named pki that enables read access to the PKI secrets engine paths.

```bash
vault policy write pki - <<EOF
path "pki*"                        { capabilities = ["read", "list"] }
path "pki/sign/example-dot-com"    { capabilities = ["create", "update"] }
path "pki/issue/example-dot-com"   { capabilities = ["create"] }
EOF
```
Enable Kubernetes Auth
```bash
vault auth enable kubernetes

vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"
```

#### Create issuer role
```bash
vault write auth/kubernetes/role/issuer \
    bound_service_account_names=issuer \
    bound_service_account_namespaces=default,istio-system \
    policies=pki \
    ttl=20m
```
Create issuer service account in k8s
```bash
kubectl create serviceaccount issuer
kubectl create serviceaccount issuer -n istio-system
```

Create Secret token
```bash
kubectl apply -f charts/issuer-secret.yaml

ISSUER_SECRET_REF=$(kubectl get secrets --output=json | jq -r '.items[].metadata | select(.name|startswith("issuer-token-")).name')
```

Create a vault issuer
```bash
kubectl apply -f charts/vault-issuer.yaml
```
Create certificate
```bash
kubectl apply -f charts/example-dot-com-cert.yaml
```

### Mutual TLS
Retrieve certificates from cert-manager for mtls client
```bash
kubectl get secret <secret_name> -n <namespace> -o jsonpath='{.data.tls\.crt}' | base64 -d > client.crt
kubectl get secret <secret_name> -n <namespace> -o jsonpath='{.data.tls\.key}' | base64 -d > client.key
```

#### Call services

```bash
INGRESS_NAME='istio-ingressgateway'
INGRESS_NS='istio-system'
export INGRESS_HOST=$(kubectl -n "$INGRESS_NS" get service "$INGRESS_NAME" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
export INGRESS_PORT=$(kubectl -n "$INGRESS_NS" get service "$INGRESS_NAME" -o jsonpath='{.spec.ports[?(@.name=="http2")].port}')
export SECURE_INGRESS_PORT=$(kubectl -n "$INGRESS_NS" get service "$INGRESS_NAME" -o jsonpath='{.spec.ports[?(@.name=="https")].port}')
export TCP_INGRESS_PORT=$(kubectl -n "$INGRESS_NS" get service "$INGRESS_NAME" -o jsonpath='{.spec.ports[?(@.name=="tcp")].port}')

curl -v -HHost:www.example.com --resolve "www.example.com:$SECURE_INGRESS_PORT:$INGRESS_HOST" \
  --cacert ./certs/root/example.com.crt "https://www.example.com:$SECURE_INGRESS_PORT/status/418"
```