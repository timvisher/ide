delete_known_host_line () {
    sed -i".bak$(date -u '+%FT%TZ')" "$1"'d' ~/.ssh/known_hosts
}

_ideEXP_ssh_config_bastion() {
  cat <<'EOF'
# If your local username doesn't match your username in production, you
# can either change your local username or add a section like the
# following to ~/.ssh/config
#
# Match host stitch-*,*.stitchdata.com,10.2.*
#   User <your production username> # like `User tvisher`

Host stitch-bastion
  HostName bastion.stitchdata.com
  # Always forward my agent
  ForwardAgent yes
  # Don't wait around for awhile
  ConnectTimeout 5
  # These boxes change all the time and we don't care
  StrictHostKeyChecking no
  CheckHostIP no
  UpdateHostKeys no
  UserKnownHostsFile /dev/null
  # Any time we establish a connection to this host (bastion), so long as
  # that connection is live, reuse it instead of establishing a new
  # one.
  ControlMaster auto
  ControlPath /tmp/ssh_mux_%h_%p_%r
  # By default, ControlMaster will terminate the shared connection as
  # soon as there are no more active connections to the server. This
  # gives us a 10 minute window after the last connection is closed
  # where we can continue to piggyback on it.
  ControlPersist 10m
  # I never want to hear about your problems, ssh, until I do.
  LogLevel QUIET

# stitch-prod AWS Primary VPC
Match host 10.2.*,stitch-*
  # Magic!
  #
  # We can 'directly' connect to the hosts that `bastion` protects by
  # using bastion to tunnel the traffic.
  ProxyJump stitch-bastion
  # forward your agent up to interact with git and ssh past the bastion.
  ForwardAgent yes
  # Don't wait around for awhile
  ConnectTimeout 5
  # These boxes change all the time and we don't care
  StrictHostKeyChecking no
  CheckHostIP no
  UpdateHostKeys no
  UserKnownHostsFile /dev/null
  # I never want to hear about your problems, ssh, until I do.
  LogLevel QUIET
EOF
}

_ideEXP_ssh_config_sandbox_instances() {
cat <<EOF
Host stitch-sandbox-app
  HostName sandbox-bastion-2103608998.us-east-1.elb.amazonaws.com
  ServerAliveInterval 50
  ConnectTimeout 5
  LogLevel QUIET
  StrictHostKeyChecking no
  CheckHostIP no
  UpdateHostKeys no
  UserKnownHostsFile /dev/null

Host stitch-tap-tester-sandbox-app
  HostName sandbox-tap-tester-app-396975488.us-east-1.elb.amazonaws.com 
  ServerAliveInterval 50
  ConnectTimeout 5
  LogLevel QUIET
  StrictHostKeyChecking no
  CheckHostIP no
  UpdateHostKeys no
  UserKnownHostsFile /dev/null
EOF
}

_ideEXP_ssh_config_opsworks_instances() {
  ide_aws_opsworks_instance_ips |
    jq -r '"Host stitch-\(.Hostname | gsub("_"; "-"))\n  HostName \(.PrivateIp)\n"'
}

_ideEXP_hosts_file_opsworks_instances() {
  ide_aws_opsworks_instance_ips |
    jq -r '"\(.PrivateIp) stitch-\(.Hostname)"'
}

_ideEXP_ssh_config_opsworks_layers() {
  local layer_names_by_id
  layer_names_by_id=$(ide_aws_opsworks_describe_layers |
                        jq -s 'map({(.LayerId): .Name})
                               | add'
                     )
  ide_aws_opsworks_describe_instances |
    jq -r -s 'map(select(.PrivateIp)
                  | select(.Status == "online"))
              | group_by(.LayerIds[0])[]
              | .[0]
              | {
                  layer:
                  '"$layer_names_by_id"'[.LayerIds[0]],

                  PrivateIp
                }
              # Must remove bastion to prevent infinite ProxyJump loop
              | select(.layer != "bastion")
              | "Host stitch-\(.layer | gsub("_"; "-"))\n  HostName \(.PrivateIp)\n"'
}

_ideEXP_hosts_file_opsworks_layers() {
  local layer_names_by_id
  layer_names_by_id=$(ide_aws_opsworks_describe_layers |
                        jq -s 'map({(.LayerId): .Name})
                               | add'
                   )
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

_ideEXP_ssh_config_k8s_nodes() {
  cat <<EOF
Match host stitch-nodes*,stitch-*-eks*
  ForwardAgent yes
  ConnectTimeout 5
  StrictHostKeyChecking no
  LogLevel QUIET
  UpdateHostKeys no
  UserKnownHostsFile /dev/null

Match host stitch-nodes*
  User admin

Host stitch-staging-kube-bastion
  HostName bastion.staging-kube.stitchdata.com
  StrictHostKeyChecking no
  LogLevel QUIET
  UpdateHostKeys no
  UserKnownHostsFile /dev/null
  ServerAliveInterval 50
  User admin

Match host stitch-*-eks*
  ProxyJump stitch-staging-kube-bastion
  User ec2-user
EOF

  local node_groups=(
    'nodes.kube.stitchdata.com'
    'nodes.staging-kube.stitchdata.com'
    'production_eks'
    'staging_eks'
  )

  aws_as_describe_groups_instances "${node_groups[@]}" |
    jq -r 'select(.PrivateIpAddress)
           | {
               PrivateIpAddress,
               Name:
               ("stitch-\(.Tags|from_entries|.Name)-\(.PrivateIpAddress)"|gsub("[\\._]"; "-"))
             }
           | "Host \(.Name)\n  HostName \(.PrivateIpAddress)\n"'

  aws_as_describe_groups_instances "${node_groups[@]}" |
    jq -rs 'map(select(.PrivateIpAddress)
                | {
                    PrivateIpAddress,
                    Name: "stitch-\(.Tags|from_entries|.Name|gsub("[\\._]"; "-"))"
                  }
            )
            | group_by(.Name)[]
            | .[0]
            | "Host \(.Name)\n  HostName \(.PrivateIpAddress)\n"'
}

_ideEXP_hosts_file_k8s_nodes() {
  local node_groups=(
    'nodes.kube.stitchdata.com'
    'nodes.staging-kube.stitchdata.com'
    'production_eks'
    'staging_eks'
  )

  aws_as_describe_groups_instances "${node_groups[@]}" |
    jq -r 'select(.PrivateIpAddress)
           | {
               PrivateIpAddress,
               Name: (
                 "stitch-\(.Tags|from_entries|.Name)-\(.PrivateIpAddress)"
                 | gsub("[\\._]"; "-")
               )
             }
           | "\(.PrivateIpAddress) \(.Name)"'

  aws_as_describe_groups_instances "${node_groups[@]}" |
    jq -rs 'map(
              select(.PrivateIpAddress)
              | {
                  PrivateIpAddress,
                  Name: (.Tags|from_entries|.Name|gsub("[\\._]"; "-"))
                }
            )
            | group_by(.Name)[]
            | .[0]
            | "\(.PrivateIpAddress) stitch-\(.Name)"'
}

_ideEXP_ssh_config_all() {
  eval "$(compgen -A function _ideEXP_ssh_config_ | grep -v '_all$')"
}

_ideEXP_hosts_file_all() {
  eval "$(compgen -A function _ideEXP_hosts_file_ | grep -v '_all$')"
}
