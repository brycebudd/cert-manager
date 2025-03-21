# Vault Secret Configuration

# Enable the Secret Engine for Workload
The remainder of this guide assumes you are logged into an existing vault cluster via the Vault CLI. You can find instructions [here](./vault-cluster-setup.md#login-to-vault).

```bash
vault secrets enable -path=appid kv-v2
```

# Store Secrets for Workload

## Certificates
```bash
vault kv put appid/component/certificates \
  tls.crt=@./certs/cluster-a-intermediate-ca.crt \
  tls.key=@./certs/cluster-a-intermediate-ca.key
```

## Other Secrets
```bash
vault kv put appid/component/credentials \
  username="some.user" \
  password="s3cr3tP@ssw0rd"
```

# Configure Vault Policy for Accessing Secrets
```bash
vault policy write app-secrets-readonly - <<EOF
path "appid/*" {
  capabilities = ["read"]
}
EOF
```

# Configure Workload Role to Access Secrets
This assumes you have already configured [Vault Kubernetes Authentication](./vault-kubernetes-authentication.md) for your cluster.

```bash
vault write auth/cluster-a/role/appid \
    bound_service_account_names=appid-sa \
    bound_service_account_namespaces=default \
    policies=app-secrets-readonly \
    ttl=24h
```

# Next Steps

- [Use Vault Secret Injection](./use-cases/vault-secret-injection.md)
- [Use Vault Secret Operator](./use-cases/vault-secret-operator.md)