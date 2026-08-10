# outputs module

This directory is reserved for any cross-cutting output aggregation that doesn't belong
to a specific module. In the current implementation, all outputs are defined directly
in each environment's `outputs.tf` file, which imports values from sub-module outputs.

This module exists as a placeholder for future use, such as:
- Generating an Ansible inventory file from Terraform outputs
- Producing a kubeadm config template with injected IPs
- Cross-module output documentation
