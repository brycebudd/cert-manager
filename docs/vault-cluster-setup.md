# Vault Cluster Setup
This guide describes how to setup a vault cluster suitable for storing secrets and issuing certificates multiple kubernetes clusters. Any deviations from best practices will be clearly noted. We encourage you to read the [Vault documentation](https://developer.hashicorp.com/vault) for current guidance.

# Principles
- Use Vault for secret storage over Kubernetes Secrets
- Use cluster specific intermediate CAs for certficiate issuance
  ```java
  Root CA (Offline/Secured)
    ├── Intermediate CA (Stored in Vault)
      ├── cluster A Intermediate CA (Vault PKI Engine)
      ├── cluster B Intermediate CA (Vault PKI Engine)
      ├── cluster C Intermediate CA (Vault PKI Engine)
  ```
- Strong Isolation: Each cluster has its own distinct authentication and authorization for PKI.
- Least Privilege: Policies are tailored to the specific needs of each cluster.
- Improved Security: Reduces the risk of unintended access or privilege escalation.
- Clear Auditing: Vault audit logs will show which cluster performed which actions.

# Installation
Use the makefile to setup a kubernetes cluster (kind) for deploying vault. 

## Create Kubernetes Cluster
```bash
make CLUSTER_NAME=vault cluster
```
> **Warning**
>
> *This is not suitable for a production deployment.* 
>

## Install Vault CLI
Install the vault cli on your developer workstation. We will use this later to connect and configure the vault instance deployed to kubernetes.

```bash
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install vault
```

## Install Vault to Kubernetes

```bash
make CLUSTER_NAME=vault install-vault-cluster
make CLUSTER_NAME=vault expose-vault-cluster #optional

```
> **WARNING**
>
> *This is not suitable for a production deployment.*  
> See [Appendix](#appendix) for standard setup.
>

## Login to Vault

### Using Vault CLI on Separate Machine

```bash
#optional: may be needed based on your network setup (i.e. virtual machine)
kubectl --context kind-vault port-forward pod/vault-0 8200:8200 & #fork to background 

# in a separate terminal execute...
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root' #assumes default dev mode token, otherwise use assigned

vault login
```

### Login Directly to Kubernetes Instance
```bash
kubectl exec -it vault-0 -- /bin/sh
vault login $VAULT_DEV_ROOT_TOKEN_ID
```

# Next Steps

- [Vault PKI Configuration](./vault-pki-configuration.md)
- [Vault Secret Configuration](./vault-secret-configuration.md)

# Appendix

## Vault Kubernetes Setup (Standard Mode)
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com

helm repo update

helm install vault hashicorp/vault --set "injector.enabled=false"
```
> **INFO**  
> Alternatively pass in this [values](https://github.com/hashicorp-education/learn-vault-secrets-operator/blob/main/vault/vault-values.yaml) file.  
> 
> `helm install vault hashicorp/vault --values vault-values.yaml`  

Verify with `kubectl get pods` and `kubectl get service`. Note: default namespace assumed.

### Unseal Vault
```bash
kubectl exec vault-0 -- vault operator init -key-shares=1 -key-threshold=1 \
      -format=json > init-keys.json
```

### Set root token to ENV variable
```bash
VAULT_UNSEAL_KEY=$(cat init-keys.json | jq -r ".unseal_keys_b64[]")

kubectl exec vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY
```

### Set Root Token
```bash
cat init-keys.json | jq -r ".root_token"

VAULT_ROOT_TOKEN=$(cat init-keys.json | jq -r ".root_token")

kubectl exec vault-0 -- vault login $VAULT_ROOT_TOKEN
```

### TODO
- Extend this guide with auto-unseal processes and procedures.
