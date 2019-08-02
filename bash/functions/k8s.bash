# shellcheck source=bash/functions/_deprecation.bash
source ~/git/ide/bash/functions/_deprecation.bash

k8s_proxy() {
    _ide_deprecated ide_k8s_proxy
}

ide_k8s_proxy() {
    ide_menagerie_ssh_instance kubectl proxy --port 5018
}

k8s_kubectl_shell() {
    _ide_deprecated ide_k8s_kubectl_shell
}

ide_k8s_kubectl_shell() {
    ide_menagerie_ssh_instance
}

k8s_ssh_node_instances() {
    _ide_deprecated ide_k8s_ssh_node_instances
}

ide_k8s_ssh_node_instances() {
    aws_as_describe_groups_instances 'nodes.kube.stitchdata.com' \
        | jq -r '"ssh admin@\(.PrivateIpAddress) # \(.InstanceId)"'
}

ide_k8s_ssh_node_instance() {
  eval "$(aws_as_describe_groups_instances 'nodes.kube.stitchdata.com' \
           | jq -sr '.[0]
                     | @sh "ssh admin@\(.PrivateIpAddress) # \(.InstanceId)"')"
}

ide_k8s_nodes_multi_exec() {
    local instance_ips=()

    while read -r ip
    do
        if [[ -n "$ip" ]]
        then
            instance_ips+=("$ip")
        fi
    done < <(aws_as_describe_groups_instances 'nodes.kube.stitchdata.com' \
                 | jq -r '.PrivateIpAddress')

    parallel -j 0 "ssh admin@'{}' 'hostname; $*'" ::: "${instance_ips[@]}"
}

ssh_k8s_node_instances() {
    _ide_deprecated ide_ssh_k8s_node_instances
}

ide_ssh_k8s_node_instances() {
    ide_k8s_ssh_node_instances
}

k8s_ssh_instance() {
    _ide_deprecated ide_k8s_ssh_instance "@"
}

ide_k8s_ssh_instance() {
    local instance_id=$1
    shift

    local instance
    if ! instance=$(aws_as_describe_instances "$instance_id")
    then
        echo "No instance: ${instance_id}" >&2
        return 1
    fi

    # We want this to expand on the client side
    # shellcheck disable=SC2029
    ssh admin@"$(jq -r '.PrivateIpAddress' <<<"$instance")" "$@"
}

ssh_k8s_instance() {
    _ide_deprecated ide_ssh_k8s_instance "$@"
}

ide_ssh_k8s_instance() {
    ide_k8s_ssh_instance "$@"
}

_ide_k8s_terminate_instance_show_help() {
    cat <<EOF
# as admin_global
ide_k8s_terminate_instance i-xxxxxxxxxx
EOF
}

k8s_terminate_instance() {
    _ide_deprecated ide_k8s_terminate_instance "$@"
}


ide_k8s_terminate_instance() {
    local instance_id=$1

    if (( 1 < $# ))
    then
        _ide_k8s_terminate_instance_show_help
        return 1
    fi

    if ! assert_admin_global
    then
        _ide_k8s_terminate_instance_show_help
        return 1
    fi

    local instance
    if ! instance=$(aws_as_describe_instances "$instance_id")
    then
        return 1
    fi
    local instance_group
    instance_group=$(jq -r '.Tags[]
                            | select(.Key == "aws:autoscaling:groupName")
                            | .Value' <<<"$instance")
    local instance_az
    instance_az=$(jq -r '.Placement.AvailabilityZone' <<<"$instance")
    ide_k8s_ssh_instance "$instance_id" \
                         "echo -n '${instance_id} '; hostname; df -h"
    local termination_answer
    read -r \
         -p "Terminate ${instance_id} (${instance_group}/${instance_az})? [y/N] " \
         termination_answer

    if [[ y == "$termination_answer" ]]
    then
        aws_as_terminate_instance "$instance_id"
    else
        echo "Not terminating ${instance_id}" >&2
    fi
}
