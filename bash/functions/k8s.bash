k8s_proxy() {
    ssh "$(aws_bastion1_ip)" sudo -u psantaclara -i kubectl proxy --port 5018
}

k8s_kubectl_shell() {
    ssh -t "$(aws_bastion1_ip)" sudo -u psantaclara -i bash -l
}

k8s_ssh_node_instances() {
    _aws_as_describe_groups_instances 'nodes.kube.stitchdata.com' | jq -r '"ssh admin@\(.PrivateIpAddress)"'
}

ssh_k8s_instances() {
    k8s_ssh_node_instances
}
