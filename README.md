# base-helm

This repository contains the Helm charts I use and improve on a daily basis. Each time I learn something new, I incorporate it here so the charts evolve and become better with every application I manage.

### base-app

The purpose of this chart is to provide a flexible, universal Helm chart that can deploy simple services with minimal effort. It is designed to be easily adaptable to different use cases and environments, making it a reliable foundation for most applications. The chart builds on the default Helm chart and extends it to simplify common deployment patterns.

### base-np-security

This chart aims to deliver an easy-to-use, configurable solution for securing namespaces with network policies. Instead of relying on each individual application chart to manage its own network policies, this chart centralizes that responsibility within the namespace. It ensures consistent network protection across workloads and supports both standard and Cilium Network Policies, making it suitable for a wide range of Kubernetes setups.

# Public

```bash
helm pull oci://registry-1.docker.io/thedeveloper10/base-app
helm pull oci://registry-1.docker.io/thedeveloper10/base-np-security
```

### TODOs

- Add network policy
- Add deployment of custom resources
- Add role/clusterrole, rolebinding and clusterrolebinding.
