# Certificate Manager with Istio
This guide assumes you have followed [cert-manager clusterissuer setup guide](../cert-manager-clusterissuer-setup.md).

***TODO: Complete Documentation!!***


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

# Appendix

## Referencces
Followed this tutorial https://developer.hashicorp.com/vault/tutorials/archive/kubernetes-cert-manager



