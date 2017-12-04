bastion1_ip() {
    echo "$(layer_instances bastion bastion | jq -r '.Instances[0] | select(.Hostname == "bastion1") | .PublicIp')"
}

k8s_proxy() {
    ssh "$(bastion1_ip)" sudo -u psantaclara -i kubectl proxy --port 5018
}

k8s_kubectl_shell() {
    ssh -t "$(bastion1_ip)" sudo -u psantaclara -i bash -l
}
