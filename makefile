# Makefile to create a kind cluster with Istio
SHELL := /bin/bash

CLUSTER_NAME := wf-dti

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
	@kind create cluster --name $(CLUSTER_NAME) --config=kind/config.yaml
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
	@kind delete cluster --name $(CLUSTER_NAME)

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

gen-clusterA-intermediate-ca-cert: gen-intermediate-ca-cert
	@echo "create cluster A intermediate cert..."
	@mkdir -p ./certs
	@openssl genrsa -out ./certs/clusterA-intermediate-ca.key 4096
	@openssl req -new -key ./certs/clusterA-intermediate-ca.key -out ./certs/clusterA-intermediate-ca.csr -subj "/C=US/ST=California/L=San Francisco/O=Wells Fargo/OU=Digital Solutions/CN=ClusterA-Intermediate-CA"
	@openssl x509 -req -in ./certs/clusterA-intermediate-ca.csr -CA ./certs/intermediate-ca.crt -CAkey ./certs/intermediate-ca.key -CAcreateserial -out ./certs/clusterA-intermediate-ca.crt -days 1095 -sha256 -extfile <(printf "basicConstraints=CA:TRUE")
