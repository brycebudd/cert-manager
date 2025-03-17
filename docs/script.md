# Script

## Explain Vault Cluster and Cluster A
```bash
kind get clusters
```

## Show Vault UI
- auth/cluster-a/role/appid 
- policy/app-secrets-readonly
- appid/component/*

## Explain Vault Auth Cluster A
```bash
kubectl apply -f - <<EOF
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

## Create Vault Static Secrets
```bash
kubectl apply -f - <<EOF
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: app-env-tls-vault
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
  name: app-env-credential-vault
  namespace: default
spec:
  type: kv-v2

  # mount path
  mount: appid

  # path of the secret
  path: component/credentials

  # dest k8s secret
  destination:
    name: app-env-credential
    create: true

  # static secret refresh interval
  refreshAfter: 30s

  # Name of the CRD to authenticate to Vault
  vaultAuthRef: app-env-auth
EOF
```

## Verify Secrets Pulled
```bash
kubectl get secrets/app-env-tls -o yaml
kubectl get secrets/app-env-credential -o jsonpath='{.data.password}' | base64 -d
```

## Change password

- Goto Vault UI and Rotate Password
- Wait 30s
`kubectl get secrets/app-env-credential -o jsonpath='{.data.password}' | base64 -d`

## Delete vault static secret and verify kubernetes secret destroyed.
```bash
kubectl delete vaultstaticsecret app-env-tls-vault app-env-credential-vault

# check
kubectl get secrets/app-env-tls
kubectl get secrets/app-env-credential
```