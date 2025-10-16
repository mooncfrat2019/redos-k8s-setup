ansible-playbook -i inventory/hosts.yml main.yml -e '{
  "super_user": "redos",
  "host_1": "212.111.87.22",
  "host_2": "217.16.17.187",
  "host_3": "90.156.219.20",
  "in_ip_1": "10.0.3.104",
  "in_ip_2": "10.0.3.248",
  "in_ip_3": "10.0.3.155",
  "host_registry": "212.111.87.117",
  "pod_network_cidr": "10.244.0.0/16",
  "cni_plugin": "cilium",
  "skip_bundle_transfer": false,
  "need_restart": true,
  "need_k8s_prepare": true
}' --tags transfer