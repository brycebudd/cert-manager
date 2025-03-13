# Certificate Manager

This guide will show how to create a certificate management solution for multiple kubernetes clusters using vault for pki and secrets, cert-manager for application certificate issuance, and istio service mesh for TLS/MTLS for workloads. 

# Capabilities
This guide will cover the following certificate management capabilities for kubernetes workloads.

- TODO

# Use Cases
There are several use cases where these powerful technologies can be combined to provide powerful automated certificate management with guardrails in a kubernetes environment.

- TODO

# Architecture

- TODO: Create Architecture Diagram

# Contents

## Vault Cluster
1. [Vault Cluster Setup](./docs/vault-cluster-setup.md)
1. [Vault PKI Configuration](./docs/vault-pki-configuration.md)
1. [Vault Kubernetes Authentication](./docs/vault-kubernetes-authentication.md)

## Workload Cluster
1. [Workload Cluster Setup](./docs/workload-cluster-setup.md)