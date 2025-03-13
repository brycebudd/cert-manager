# Vault Kubernetes Authentication

# Enable Vault Kubenetes Authentication

TODO: change this to cluster specific kubernetes auth with --path=cluster-a etc.

```bash
vault auth enable kubernetes
```

# Configure Vault Kubernetes Authentication
TODO: edit this to create auth/cluster-a  
TODO: explain cluster-to-cluster Kubernetes APIs must be open and available.  

```bash
vault write auth/kubernetes/config \
    token_reviewer_jwt=@./token \
    kubernetes_host="https://172.18.0.6:443" \
    kubernetes_ca_cert=@./cluster-a-ca.crt \
    issuer="https://kubernetes.default.svc.cluster.local"
```

The parameters used in the above command are populated based on the workload cluster (e.g. Cluster A etc.).  
| Parameter | Description |
|:----|:----|
| **token_reviewer_jwt** | This is the token from the cluster Service Account<br>`kubectl get secret/vault-auth-secret -o jsonpath='{.data.token}' -n cert-manager \| base64 -d` |
| **kubernetes_host** | This is the externally addressable Kubernetes Host for cluster<br>`kubectl get svc/kubernetes -o jsonpath='{.status.loadBalancer.ingress[*].ip}'` |
| **kubernetes_ca_cert** | This is the ca cert for cluster service account<br>`kubectl get secret/vault-auth-secret -o jsonpath='{.data.ca\.crt}' -n cert-manager \| base64 -d`<br>*or*<br>`kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' \| base64 -d` |
| **issuer** (optional) | This is the cluster KubeAPI Issuer<br> `kubectl get --raw /.well-known/openid-configuration \| jq -r '.issuer'` |

# Configure Kubernetes Authentication Role

```bash
vault write auth/kubernetes/role/cert-issuer-cluster-a \
    bound_service_account_names=vault-auth-sa \
    bound_service_account_namespaces=cert-manager \
    policies=pki_cluster-a \
    ttl=1h

vault write auth/kubernetes/role/cert-issuer-cluster-b \
    bound_service_account_names=vault-auth-sa \
    bound_service_account_namespaces=cert-manager \
    policies=pki_cluster-b \
    ttl=1h
```

