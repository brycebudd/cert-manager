# Makefile to create a kind cluster with Istio
SHELL := /bin/bash

CLUSTER_NAME = default
LOWER_CLUSTER_NAME = $(shell echo "${CLUSTER_NAME}" | tr '[:upper:]' '[:lower:]')
UPPER_CLUSTER_NAME = $(shell echo "${CLUSTER_NAME}" | tr '[:lower:]' '[:upper:]')

.PHONY: all start-cloud-provider-kind cluster istio verify clean

all: cluster istio verify start-cloud-provider-kind 

install-cloud-provider-kind:
	@echo "Installing cloud-provider-kind..."
	@command -v go &> /dev/null || (echo "Go could not be found, please install it first."; exit 1;)
	@go install sigs.k8s.io/cloud-provider-kind@latest

start-cloud-provider-kind:
	@echo "Starting cloud provider..."
	@command -v cloud-provider-kind &> /dev/null || (echo "cloud-provider-kind could not be found, please install it first."; exit 1;)
	@cloud-provider-kind

cluster: install-cloud-provider-kind
	@echo "Creating Kind cluster..."
	@command -v kind &> /dev/null || (echo "kind could not be found, please install it first."; exit 1;)
	@command -v kubectl &> /dev/null || (echo "kubectl could not be found, please install it first."; exit 1;)
	@command -v istioctl &> /dev/null || ( \
		echo "istioctl could not be found, installing it..."; \
		curl -L https://istio.io/downloadIstio | ISTIO_VERSION=latest sh -; \
		sudo mv istio-*/bin/istioctl /usr/local/bin/; \
	)
	@kind create cluster --name ${CLUSTER_NAME} --config=kind/config.yaml
	@kubectl wait --for=condition=Ready nodes --all --timeout=120s

istio:
	@echo "Installing Istio..."
	@istioctl install -y

verify:
	@echo "Verifying Istio installation..."
	@kubectl get pods -n istio-system -n istio-system || echo "Istio pods not found. Check installation." # Check if istio-system namespace exists
	@echo "Kind cluster with Istio is ready."

clean:
	@echo "Deleting Kind cluster..."
	@kind delete cluster --name ${CLUSTER_NAME}

gen-root-cert:
	@echo "create root certificate..."
	@mkdir -p ./certs
	@openssl genrsa -aes256 -out ./certs/root-ca.key 4096
	@openssl req -x509 -new -nodes -key ./certs/root-ca.key -sha256 -days 3650 -out ./certs/root-ca.crt -subj "/C=US/ST=California/L=San Francisco/O=Wells Fargo/OU=Digital Solutions/CN=RootCA"

gen-intermediate-ca-cert: gen-root-cert
	@echo "create intermediate ca certificate..."
	@mkdir -p ./certs
	@openssl genrsa -out ./certs/intermediate-ca.key 4096
	@openssl req -new -key ./certs/intermediate-ca.key -out ./certs/intermediate-ca.csr -subj "/C=US/ST=California/L=San Francisco/O=Wells Fargo/OU=Digital Solutions/CN=IntermediateCA"
	@openssl x509 -req -in ./certs/intermediate-ca.csr -CA ./certs/root-ca.crt -CAkey ./certs/root-ca.key -CAcreateserial -out ./certs/intermediate-ca.crt -days 1825 -sha256 -extfile <(printf "basicConstraints=CA:TRUE")

gen-cluster-intermediate-ca-cert:
	@echo "create ${CLUSTER_NAME} intermediate cert..."
	@mkdir -p ./certs
	@openssl genrsa -out ./certs/${LOWER_CLUSTER_NAME}-intermediate-ca.key 4096
	@openssl req -new -key ./certs/${LOWER_CLUSTER_NAME}-intermediate-ca.key -out ./certs/${LOWER_CLUSTER_NAME}-intermediate-ca.csr -subj "/C=US/ST=California/L=San Francisco/O=Wells Fargo/OU=Digital Solutions/CN=${UPPER_CLUSTER_NAME}-Intermediate-CA"
	@openssl x509 -req -in ./certs/${LOWER_CLUSTER_NAME}-intermediate-ca.csr -CA ./certs/intermediate-ca.crt -CAkey ./certs/intermediate-ca.key -CAcreateserial -out ./certs/${LOWER_CLUSTER_NAME}-intermediate-ca.crt -days 1095 -sha256 -extfile <(printf "basicConstraints=CA:TRUE")

prep-vault-install:
	@helm repo add hashicorp https://helm.releases.hashicorp.com
	@helm repo update


install-vault-cluster: prep-vault-install
	@kubectl config use-context kind-${CLUSTER_NAME}
	@helm install vault hashicorp/vault -n vault --create-namespace --values vault-values.yaml
	@kubectl get pods -n vault

expose-vault-cluster:
	@kubectl --context=kind-${CLUSTER_NAME} patch svc vault -n vault --type=json -p '[{"op":"replace","path":"/spec/type","value":"LoadBalancer"}]'

expose-cluster-a:
	@kubectl --context=kind-${CLUSTER_NAME} patch svc kubernetes -n default --type=json -p '[{"op":"replace","path":"/spec/type","value":"LoadBalancer"}]'

uninstall-vault:
	@kubectl config use-context kind-${CLUSTER_NAME}
	@helm uninstall vault -n vault
	@kubectl delete ns vault
	@sleep 10	

status-vault:
	@kubectl --context kind-${CLUSTER_NAME} exec -n vault -ti vault-0 -- vault status

logs-vault:
	@kubectl --context kind-${CLUSTER_NAME} logs -n vault sts/vault -f

health-vault:
	@kubectl --context kind-${CLUSTER_NAME} exec -n vault -ti vault-0 -- wget -qO - http://localhost:8200/v1/sys/health	

vars-vault-cli:
	@echo "export VAULT_ADDR='http://127.0.0.1:8200'"
	@echo "export VAULT_TOKEN='root'"	

install-vault-secrets-operator:
	@helm install vault-secrets-operator hashicorp/vault-secrets-operator \
		-n vault-secrets-operator-system \
		--create-namespace \
		--values vault-operator-values.yaml
	@sleep 10
	@kubectl wait --for=jsonpath='{.status.phase}'=Running pod \
		--all --namespace vault-secrets-operator-system --timeout=1m
	@kubectl wait --for=jsonpath='{.status.phase}'=Running pod --all --namespace vault-secrets-operator-system --timeout=1m
	@sleep 10

uninstall-vault-secrets-operator:
	@helm uninstall vault-secrets-operator -n vault-secrets-operator-system

logs-vso:
	@kubectl logs -n vault-secrets-operator-system -l app.kubernetes.io/name=vault-secrets-operator -f	

# config-vault:
#	@vault auth enable -path cluster-a kubernetes
#	@vault write auth/cluster-a/config \
	    token_reviewer_jwt="" \
		kubernetes_host="http://172.18.0.12:6443" \
		kubernetes_cacert=""
#	@vault secrets enable -path=appid kv-v2
#	@vault policy write appid-kv-ro - <<EOF
#       path "appid/*" {
#            capabilities = ["read"]
#        }
#        EOF
#	@vault write auth/cluster-a/role/appid \
   		bound_service_account_names=appid-sa \
   		bound_service_account_namespaces=default \
   		policies=appid-kv-ro \
   		audience=vault \
   		token_period=2m
#	@vault kv put appid/component/credentials/config username="some.user" password="some.password"	

events:
	@kubectl get events --all-namespaces --sort-by='.metadata.creationTimestamp' -w	

show-jwt:
	@echo "headers\n\n"
	@kucctl get secret app-default-token -n app-dev -o jsonpath='{.data.token}' | base64 -d | cut -d '.' -f1 | base64 -d 2>/dev/null
	@echo "\npayload\n\n"
	@kucctl get secret app-default-token -n app-dev -o jsonpath='{.data.token}' | base64 -d | cut -d '.' -f2 | base64 -d 2>/dev/null