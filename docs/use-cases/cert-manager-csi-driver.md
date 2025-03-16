# Cert-Manager CSI Driver
This guide assumes you have completed the [cert-manager clusterissuer setup](../cert-manager-clusterissuer-setup.md).

# Install Cert-Manager CSI Driver

```bash
helm repo add jetstack https://charts.jetstack.io --force-update
helm upgrade cert-manager-csi-driver jetstack/cert-manager-csi-driver \
  --install \
  --namespace cert-manager \
  --wait
```

# Usage
Add a cert-manager enabled volume to your pod. This example will use our newly minted vault issuer.

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata: 
  name: csi-app
  namespace: default
  labels:
    app: csi-app
spec:
  containers:
  - name: app
    image: busybox
    volumeMounts:
    - mountPath: "/tls"
      name: tls
    command: [ "sleep", "1000000" ]
  volumes:
  - name: tls
    csi:
      driver: csi.cert-manager.io
      readOnly: true
      volumeAttributes:
        csi.cert-manager.io/issuer-name: vault-issuer
        csi.cert-manager.io/issuer-kind: ClusterIssuer
        csi.cert-manager.io/common-name: csi-app.domain.net
        csi.cert-manager.io/dns-names: csi-app.nonprod.cluster-a.domain.net
EOF
```

See [Appendix](#deploy-nginx-with-csi-driver-issued-certificate) for an advanced usage scenario with nginx.

## Validate Certificate Issued
```bash
kubectl exec -it pod/csi-app -- /bin/sh

$ cd /tls
$tls ls
$tls ca.crt, tls.crt, tls.key
$tls exit

kubectl get certificaterequests

kubectl delete pod/app

kubectl get certificaterequests

<empty response>!!!

```

# Appendix

## Deploy nginx with CSI Driver Issued Certificate

```bash
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:latest
        ports:
        - containerPort: 443
        volumeMounts:
        - name: tls-secret
          mountPath: /etc/nginx/ssl
          readOnly: true
        - name: config-volume
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: config-volume
        configMap:
          name: nginx-config
      - name: tls-secret
        csi:
          driver: csi.cert-manager.io
          readOnly: true
          volumeAttributes:
            csi.cert-manager.io/issuer-name: vault-issuer
            csi.cert-manager.io/issuer-kind: ClusterIssuer
            csi.cert-manager.io/common-name: nginx.domain.net
            csi.cert-manager.io/dns-names: nginx.nonprod.cluster-a.domain.net          
---
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
spec:
  type: LoadBalancer # or NodePort, ClusterIP, depending on your needs
  selector:
    app: nginx
  ports:
  - protocol: TCP
    port: 443
    targetPort: 443
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  default.conf: |
    server {
        listen 443 ssl;
        server_name nginx.domain.net; # Replace with your domain

        ssl_certificate /etc/nginx/ssl/tls.crt;
        ssl_certificate_key /etc/nginx/ssl/tls.key;

        location / {
            return 200 'Hello, World!\n';
        }
    }
EOF
```

### Verify nginx using TLS
```bash
# Get External IP Address of nginx loadbalancer service
export NGINX_LB_IP=kubectl get service nginx-service -o jsonpath='{.status.loadBalancer.ingress[].ip}'

# Add IP address to hosts file
echo "${NGINX_LB_IP}  nginx.domain.net" | sudo tee -a /etc/hosts

# issue request and inspect certificate
curl -kv https://nginx.domain.net
```