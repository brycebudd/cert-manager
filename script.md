# Istio CSR

# Architecture
 - Vault Cluster
    - PKI Engine
 - Cluster A
    - Cert-Manager with Istio-CSR
    - Istio 
    - Workloads

# How it works

1. Cert-Manager has an Issuer called 'vault-nonprod-issuer' in the istio-system namespace that requests certificates from Vault PKI Engine
2. Istio-CSR is an add-on to cert-manager that allows 'Istiod' to use the vault-nonprod-issuer to issue certificates for workloads.
3. Any namespace which is istio-injection=enabled will automatically receive a workload certificate from Istio.
4. Workloads do not have to change anything to receive a workload identity.

# Demo

# Create workload namespace

```bash
kubectl create namespace app-dev
```

# Enable Istio Injection

```bash
kubectl label namespace app-dev istio-injection=enabled
```
# Deploy the application service
```bash
kubectl apply \
    -f ../istio/samples/helloworld/helloworld.yaml \
    -l service=helloworld -n app-dev

kubectl get services -n app-dev
```

# Deploy the application
```bash
kubectl apply \
    -f ../isto/samples/helloworld/helloworld.yaml \
    -l version=v1 -n app-dev
```

# Deploy Curl App
This is so we can test connectivity from within the cluster (vs externally)
```bash
kubectl apply \
    -f ../istio/samples/curl/curl.yaml -n app-dev

kubectl get pods -n app-dev   
```

# Verify the application is functioning
```bash
kubectl exec -n app-dev -c curl \
    "$(kubectl get pod -n app-dev -l app=curl \
     -o jsonpath='{.items[0].metadata.name}')" \
    -- curl -sS helloworld.sample:5000/hello
```

# Verify Certificates

## Istio Root Cert
```bash
kubectl get cm istio-ca-root-cert -o jsonpath="{.data['root-cert\.pem']}" | openssl x509 -noout -text
```

## Workload Cert
```bash
NAMESPACE="app-dev"
kubectl get secrets -n ${NAMESPACE}

WORKLOAD="$(kubectl get pod -n ${NAMESPACE} -l app=helloworld -o jsonpath='{.items[0].metadata.name}')" 
istioctl proxy-config secret ${WORKLOAD} -n ${NAMESPACE} -o json | jq '.dynamicActiveSecrets[0].secret.tlsCertificate.certificateChain.inlineBytes' | sed 's/"//g' | base64 --decode | openssl x509 -noout -text
```

# Istio Discovery Endpoints
The following command will display the endpoints discovered by the Istio control plane
```bash
kubectl --namespace=istio-system exec -c discovery $(kubectl --namespace=istio-system get pods --no-headers -l app=istiod | awk '{print $1}') -- curl --max-time 10 -s http://127.0.0.1:8080/debug/endpointShardz
```
