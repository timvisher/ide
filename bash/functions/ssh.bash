delete_known_host_line () {
    sed -i".bak$(date -u '+%FT%TZ')" "$1"'d' ~/.ssh/known_hosts
}

ide_ssh_regenerate_stitch_opsworks_config() {
  mkdir -p ~/.ssh/config.d
  while read -r stack_id
  do
    aws opsworks describe-instances --stack-id "$stack_id"
  done < <(stack_ids) \
    | > ~/.ssh/config.d/stitch_opsworks \
        jq -r '.Instances[]
               | select(.PrivateIp)
               | "Host \(.Hostname)\n  HostName \(.PrivateIp)\n"'
}
