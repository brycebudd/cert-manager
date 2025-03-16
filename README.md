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

## Vault Cluster Setup
1. [Vault Cluster Setup](./docs/vault-cluster-setup.md)
    - [Vault PKI Configuration](./docs/vault-pki-configuration.md) *(required for cert-manager)*
    - [Vault Secret Configuration](./docs/vault-secret-configuration.md) *(required for secrets management)*
1. [Vault Kubernetes Authentication](./docs/vault-kubernetes-authentication.md)

## Workload Cluster Setup

[Cert-Manager Multi-Cluster Issuer with Vault](./docs/cert-manager-clusterissuer-setup.md)

### Cert-Manager
1. [Cert-Manager CSI Driver](./docs/use-cases/cert-manager-csi-driver.md)
1. [Cert-Manager Istio CSR](./docs/use-cases/cert-manager-istio.md) - **In-Progress**

### Secrets Management
1. [Vault Secret Injection](./docs/use-cases/vault-secret-injection.md)
1. [Vault Secret Operator](./docs/use-cases/vault-secret-operator.md) - **TODO**
