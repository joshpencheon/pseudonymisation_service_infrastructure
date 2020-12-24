# Pseudonymisation Service: Infrastructure

This repository contains proof-of-concept code for deploying NDR's [pseudonymisation service](https://github.com/joshpencheon/pseudonymisation_service) to a Kubernetes cluster, using Terraform.

## Gotchas

### GitHub API access

The `github` provider doesn't work properly without authentication.

Export a token (read-only is fine) as `$GITHUB_TOKEN` before running any Terraform commands.


### `*.test` DNS resolution

The behaviour of this repository is to have a Terraform workspace per development branch, and to deploy
each into a separate k8s namespace. Ingress is then used to make each accessible on separate subdomains,
via Host-based routing:

```
curl <branch_name>.pseudonymise.test/api/v1/keys
```

In order for this to work, these domains must resolve. When using Minikube / `ingress-nginx`, they must
resolve to the Minikube VM's IP (accessible via `minikube ip`).

On macOS, you could install `dnsmasq` (as a service, via Homebrew) and add the following config:

```
# in /usr/local/etc/dnsmasq.conf
address=/pseudonymise.test/ip.of.minitest.vm
```

and then add your local machine as a resolver for `.test`:

```
sudo bash -c 'echo "nameserver 127.0.0.1" > /etc/resolver/test'
```

You should then be able to both resolve and ping:

```
dig wibble.pseudonymise.test @127.0.0.1

ping wibble.pseudonymise.test
```
