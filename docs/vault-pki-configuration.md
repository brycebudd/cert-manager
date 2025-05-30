# Vault PKI Configuration
This guide describes how to configure vault PKI for storing Intermediate CA and Cluster Specific CA certificates.

# Enable the PKI secret engine

```bash
vault secrets enable pki
vault secrets tune -max-lease-ttl=87600h pki
```

## Configure Issuing Certificates and Certificate Revocation Distribution List

```bash
vault write pki/config/urls \
    issuing_certificates="http://vault.default:8200/v1/pki/ca" \
    crl_distribution_points="http://vault.default:8200/v1/pki/crl"
```

## Generate the Root CA Certificate

```bash
vault write pki/root/generate/internal \
    common_name="RootCA" \
    ttl=87600h
```

> **WARNING**
>
> We are storing the Root CA in Vault for this guide to show how to manage certificates in vault, but in a production environment you should store the root certificate offline.
>

# Setup Intermediate CA

```bash
vault secrets enable -path=pki_int pki
vault secrets tune -max-lease-ttl=43800h pki_int
```

## Generate Intermediate CA Signing Request

```bash
vault write -format=json pki_int/intermediate/generate/internal \
     common_name="IntermediateCA" \
     ttl=43800h \
     | jq -r '.data.csr' > pki_int.csr
```

## Sign the Intermediate CA with the Root Certificate

```bash
vault write -format=json pki/root/sign-intermediate \
     csr=@pki_int.csr \
     format=pem_bundle \
     ttl=43800h \
     | jq -r '.data.certificate' > intermediate.pem    
```

## Import the Signed Certificate

```bash
vault write pki_int/intermediate/set-signed \
    certificate=@intermediate.pem    
```

# Create the cluster Specific Intermediate CAs

```bash
vault secrets enable -path=pki_cluster-a pki
vault secrets enable -path=pki_cluster-b pki
```

## Generate the Certificate Signing Request for each cluster

```bash
vault write -format=json pki_cluster-a/intermediate/generate/internal \
    common_name="Cluster-A Intermediate CA" \
    ttl=21900h \
    | jq -r '.data.csr' > cluster-a.csr

vault write -format=json pki_cluster-b/intermediate/generate/internal \
    common_name="Cluster-B Intermediate CA" \
    ttl=21900h \
    | jq -r '.data.csr' > cluster-b.csr    
```

## Sign cluster Specific Intermediate CA with Intermediate CA

```bash
vault write -format=json pki_int/root/sign-intermediate \
    csr=@cluster-a.csr \
    format=pem_bundle \
    ttl=21900h \
    | jq -r '.data.certificate' > cluster-a-intermediate.pem    

vault write -format=json pki_int/root/sign-intermediate \
    csr=@cluster-b.csr \
    format=pem_bundle \
    ttl=21900h \
    | jq -r '.data.certificate' > cluster-b-intermediate.pem    
```

## Import cluster-Specific Intermediate CA Certificates

```bash
vault write pki_cluster-a/intermediate/set-signed \
    certificate=@cluster-a-intermediate.pem

vault write pki_cluster-b/intermediate/set-signed \
    certificate=@cluster-b-intermediate.pem
```

# Configure Cluster Specific Certificate Issuance

## Setup Certificate Issuance Roles
Here you can define roles which will be used to issue cluster certificates. The idea conveyed here is to separate roles by usage or other factors unique to your environment. Here we are showcasing using nonprod and prod roles to create certificates for different domains.

```bash
vault write pki_cluster-a/roles/nonprod \
allowed_domains=domain.net \
allow_any_name=true \
enforce_hostnames=false \
require_cn=false \
allowed_uri_sans="spiffe://*" \
max_ttl=72h

vault write pki_cluster-a/roles/nonprod \
    allowed_domains=domain.net \
    allow_subdomains=true \
    max_ttl=72h


vault write pki_cluster-a/roles/prod \
allowed_domains=domain.com \
allow_any_name=true \
enforce_hostnames=false \
require_cn=false \
allowed_uri_sans="spiffe://*" \
max_ttl=72h

vault write pki_cluster-a/roles/prod \
    allowed_domains=domain.com \
    allow_subdomains=true \
    max_ttl=72h    


vault write pki_cluster-b/roles/nonprod \
allowed_domains=domain.net \
allow_any_name=true \
enforce_hostnames=false \
require_cn=false \
allowed_uri_sans="spiffe://*" \
max_ttl=72h

vault write pki_cluster-b/roles/nonprod \
    allowed_domains=domain.net \
    allow_subdomains=true \
    max_ttl=72h


vault write pki_cluster-b/roles/prod \
allowed_domains=domain.com \
allow_any_name=true \
enforce_hostnames=false \
require_cn=false \
allowed_uri_sans="spiffe://*" \
max_ttl=72h

vault write pki_cluster-b/roles/prod \
    allowed_domains=domain.com \
    allow_subdomains=true \
    max_ttl=72h    
```
## Setup Vault Policy for Cluster Workloads

Create a named policy that enables read access to the PKI secrets engine paths. *Note: Only showing policy for nonprod role.*

```bash
vault policy write pki_cluster-a - <<EOF
path "pki*"                          { capabilities = ["read", "list"] }
path "pki_cluster-a/roles/nonprod"   { capabilities = ["create", "update"] }
path "pki_cluster-a/sign/nonprod"    { capabilities = ["create", "update"] }
path "pki_cluster-a/issue/nonprod"   { capabilities = ["create"] }
EOF

vault policy write pki_cluster-b - <<EOF
path "pki*"                          { capabilities = ["read", "list"] }
path "pki_cluster-b/roles/nonprod"   { capabilities = ["create", "update"] }
path "pki_cluster-b/sign/nonprod"    { capabilities = ["create", "update"] }
path "pki_cluster-b/issue/nonprod"   { capabilities = ["create"] }
EOF
```

# Next Steps

[Setup Vault Kubernetes Authentication](./vault-kubernetes-authentication.md)
