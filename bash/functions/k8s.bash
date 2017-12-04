# shellcheck shell=bash

_k8s_bastion1_ip() {
    layer_instances bastion bastion | jq -r '.Instances[0] | select(.Hostname == "bastion1") | .PublicIp'
}

k8s_proxy() {
    ssh "$(_k8s_bastion1_ip)" sudo -u psantaclara -i kubectl proxy --port 5018
}

k8s_kubectl_shell() {
    ssh -t "$(_k8s_bastion1_ip)" sudo -u psantaclara -i bash -l
}
