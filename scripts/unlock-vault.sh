VAULT_UNSEAL_KEY=$(cat ./vault-seal.json | jq -r ".unseal_keys_b64[]")
kubectl exec vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY

VAULT_ROOT_TOKEN=$(cat ./vault-seal.json | jq -r ".root_token")
kubectl exec vault-0 -- vault login $VAULT_ROOT_TOKEN
