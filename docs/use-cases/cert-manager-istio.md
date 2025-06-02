# Certificate Manager with Istio

# istio-csr

cert-manager-istio-csr is an agent which allows for [istio](https://istio.io) workload and control plane components to be secured using
[cert-manager](https://cert-manager.io). Certificates facilitating mTLS, inter and intra cluster, will be signed, delivered and renewed
using [cert-manager issuers](https://cert-manager.io/docs/concepts/issuer).

# Installation

1. Firstly, [cert-manager must be installed](https://cert-manager.io/docs/installation/) in your cluster. An issuer must be configured,
which will be used to sign your certificate workloads. This guide assumes you have followed
[cert-manager clusterissuer setup guide](../cert-manager-clusterissuer-setup.md).

2. Next, install the `cert-manager-istio-csr` into the cluster, and configure `--set app.certmanager.issuer.name=vault-nonprod-issuer` to [use
the Issuer](../cert-manager-clusterissuer-setup.md) that we have
previously created. The Issuer must reside in the same namespace as that configured by `-c, --certificate-namespace`, which
is `istio-system` by default.

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

CTX_CLUSTER1="kind-cluster-a"
CTX_CLUSTER2="kind-cluster-b"

# Cluster 1
helm --kube-context="${CTX_CLUSTER1}" install -n cert-manager cert-manager-istio-csr jetstack/cert-manager-istio-csr --set app.server.clusterID=cluster1 --set app.certmanager.issuer.name=vault-nonprod-issuer --set app.certmanager.preserveCertificateRequests=true --set app.logLevel=3helm --kube-context="${CTX_CLUSTER1}" install -n cert-manager cert-manager-istio-csr jetstack/cert-manager-istio-csr --set app.server.clusterID=cluster1 --set app.certmanager.issuer.name=vault-nonprod-issuer --set app.certmanager.preserveCertificateRequests=true --set app.logLevel=3helm --kube-context="${CTX_CLUSTER1}" install -n cert-manager cert-manager-istio-csr jetstack/cert-manager-istio-csr --set app.server.clusterID=cluster1 --set app.certmanager.issuer.name=vault-nonprod-issuer --set app.certmanager.preserveCertificateRequests=true --set app.logLevel=3

# Cluster 2
helm --kube-context="${CTX_CLUSTER2}" install -n cert-manager cert-manager-istio-csr jetstack/cert-manager-istio-csr --set app.server.clusterID=cluster2 --set app.certmanager.issuer.name=vault-nonprod-issuer --set app.certmanager.preserveCertificateRequests=true --set app.logLevel=3
```

<br> 

3. Finally, install istio.

```bash
# Cluster1
istioctl --context="${CTX_CLUSTER1}" install -f resources/istio-config-cluster-1-1.yaml

# Cluster2 
istioctl --context="${CTX_CLUSTER2}" install -f resources/istio-config-cluster-2-1.yaml
```

Istio must be installed using the IstioOperator
configuration changes within
[`resources/istio-config-x.yaml`](../resources/istio-config-cluster-1-1.yaml). These changes are
required in order for the CA Server to be disabled in istiod, ensure istio
workloads request certificates from the cert-manager agent, and the istiod
certificates and keys are mounted in from the Certificate created earlier.
<br> 
<br> 
The istio config file include also the *`multiCluster`* config where we have to set the `meshID`, `clusterName` and the `network`.

```bash
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  values:
    global:
      meshID: mesh1
      multiCluster:
        clusterName: cluster1
      network: network1
```
# Demo
[Cert-Manager with Istio Demo](https://screencast.apps.chrome/10PyZgJ1jWFgCUCUmBXeBimoxbAPg8JpT?createdTime=2025-05-30T23%3A18%3A40.729Z)

# Appendix

## Calling services externally (mTLS)

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

## References
- https://github.com/brycebudd/istio-vault-ca/blob/master/README.md
- Followed this tutorial https://developer.hashicorp.com/vault/tutorials/archive/kubernetes-cert-manager



