# shellcheck shell=bash

k8s_proxy() {
    ssh "$(aws_bastion1_ip)" sudo -u psantaclara -i kubectl proxy --port 5018
}

k8s_kubectl_shell() {
    ssh -t "$(aws_bastion1_ip)" sudo -u psantaclara -i bash -l
}
