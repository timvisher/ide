delete_known_host_line () {
    sed -i".bak$(date -u '+%FT%TZ')" "$1"'d' ~/.ssh/known_hosts
}

ide_ssh_regenerate_stitch_opsworks_config() {
  mkdir -p ~/.ssh/config.d
  ide_aws_opsworks_instance_ips \
    | jq -r '"Host stitch-\(.Hostname | gsub("_"; "-"))\n  HostName \(.PrivateIp)\n"' \
    | tee ~/.ssh/config.d/stitch_opsworks
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
                | "Host \(.layer | gsub("_"; "-")) stitch-\(.layer | gsub("_"; "-"))\n  HostName \(.PrivateIp)\n"' \
    | tee ~/.ssh/config.d/stitch_opsworks_layer_instance
}

ide_ssh_regenerate_stitch_all_config() {
  ide_ssh_regenerate_stitch_opsworks_config
  ide_ssh_regenerate_stitch_opsworks_layer_instance_config
}
