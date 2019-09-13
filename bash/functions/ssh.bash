delete_known_host_line () {
    sed -i".bak$(date -u '+%FT%TZ')" "$1"'d' ~/.ssh/known_hosts
}

ide_ssh_regenerate_stitch_opsworks_config() {
  mkdir -p ~/.ssh/config.d
  ide_aws_opsworks_instance_ips \
    | jq -r '"Host stitch-\(.Hostname | gsub("_"; "-"))\n  HostName \(.PrivateIp)\n"' \
    | tee ~/.ssh/config.d/stitch_opsworks
}

ide_hosts_opsworks_entries() {
  mkdir -p ~/.ssh/config.d
  ide_aws_opsworks_instance_ips |
    jq -r '"\(.PrivateIp) stitch-\(.Hostname)"'
}

ide_ssh_regenerate_stitch_opsworks_layer_instance_config() {
  mkdir -p ~/.ssh/config.d
  local layer_names_by_id
  layer_names_by_id="$(ide_aws_opsworks_describe_layers \
                         | jq -s '[
                                    .[] | {(.LayerId): .Name}
                                  ]
                                  | add'
                     )"
  ide_aws_opsworks_describe_instances \
    | jq -r -s 'map(select(.PrivateIp))
                | group_by(.LayerIds[0])[]
                | .[0]
                | {
                    layer:
                    '"$layer_names_by_id"'[.LayerIds[0]],

                    PrivateIp
                  }
                # Must remove bastion to prevent infinite ProxyJump loop
                | select(.layer != "bastion")
                | "Host stitch-\(.layer | gsub("_"; "-"))\n  HostName \(.PrivateIp)\n"' \
    | tee ~/.ssh/config.d/stitch_opsworks_layer_instance
}

ide_hosts_opsworks_layer_entries() {
  local layer_names_by_id
  layer_names_by_id="$(ide_aws_opsworks_describe_layers \
                         | jq -s '[
                                    .[] | {(.LayerId): .Name}
                                  ]
                                  | add'
                     )"
  ide_aws_opsworks_describe_instances |
    jq -r -s 'map(select(.PrivateIp))
              | group_by(.LayerIds[0])[]
              | .[0]
              | {
                  layer:
                  '"$layer_names_by_id"'[.LayerIds[0]],

                  PrivateIp
                }
              # Must remove bastion to prevent infinite ProxyJump loop
              | select(.layer != "bastion")
              | "\(.PrivateIp) stitch-\(.layer | gsub("_"; "-"))"'
}

ide_ssh_regenerate_k8s_nodes_config() {
  mkdir -p ~/.ssh/config.d
  cat > ~/.ssh/config.d/staging-kube-bastion <<EOF
Match host stitch-nodes*,stitch-*_eks*
  ForwardAgent yes
  ConnectTimeout 5
  StrictHostKeyChecking no
  LogLevel QUIET
  UpdateHostKeys no
  UserKnownHostsFile /dev/null

Match host stitch-nodes*
  User admin

Host staging-kube-bastion
  HostName bastion.staging-kube.stitchdata.com
  StrictHostKeyChecking no
  LogLevel QUIET
  UpdateHostKeys no
  UserKnownHostsFile /dev/null
  ServerAliveInterval 50
  User admin

Match host stitch-*_eks*
  ProxyJump staging-kube-bastion
  User ec2-user
EOF

  local node_groups=(
    'nodes.kube.stitchdata.com'
    'nodes.staging-kube.stitchdata.com'
    'production_eks'
    'staging_eks'
  )

  aws_as_describe_groups_instances "${node_groups[@]}" \
    | jq -r '
select(.PrivateIpAddress)
| {
  PrivateIpAddress,
  Name: "\(.Tags|from_entries|.Name|gsub("[\\._]"; "-"))-\(.PrivateIpAddress|gsub("\\."; "-"))"
}
| "Host stitch-\(.Name)\n  HostName \(.PrivateIpAddress)\n"' \
    | tee ~/.ssh/config.d/stitch_k8s_nodes

  aws_as_describe_groups_instances "${node_groups[@]}" \
    | jq -rs '
[
  .[]
  | {
      PrivateIpAddress,
      Name: (.Tags|from_entries|.Name|gsub("[\\._]"; "-"))
    }
]
| group_by(.Name)[]
| .[0]
| "Host stitch-\(.Name)\n  HostName \(.PrivateIpAddress)\n"' \
         | tee ~/.ssh/config.d/stitch_k8s_asgs
}

ide_hosts_k8s_nodes_entries() {
  local node_groups=(
    'nodes.kube.stitchdata.com'
    'nodes.staging-kube.stitchdata.com'
    'production_eks'
    'staging_eks'
  )

  aws_as_describe_groups_instances "${node_groups[@]}" \
    | jq -r '
select(.PrivateIpAddress)
| {
  PrivateIpAddress,
  Name: "\(.Tags|from_entries|.Name|gsub("[\\._]"; "-"))-\(.PrivateIpAddress|gsub("\\."; "-"))"
}
| "\(.PrivateIpAddress) stitch-\(.Name)"'

  aws_as_describe_groups_instances "${node_groups[@]}" \
    | jq -rs '
[
  .[]
  | {
      PrivateIpAddress,
      Name: (.Tags|from_entries|.Name|gsub("[\\._]"; "-"))
    }
]
| group_by(.Name)[]
| .[0]
| "\(.PrivateIpAddress) stitch-\(.Name)"'
}

ide_ssh_regenerate_stitch_all_config() {
  ide_ssh_regenerate_stitch_opsworks_config
  ide_ssh_regenerate_stitch_opsworks_layer_instance_config
  ide_ssh_regenerate_k8s_nodes_config
}

ide_hosts_all_entries() {
  ide_hosts_k8s_nodes_entries
  ide_hosts_opsworks_layer_entries
  ide_hosts_opsworks_entries
}
