stack_names() {
    aws opsworks describe-stacks | jq --compact-output --raw-output --monochrome-output '.Stacks[] | .Name'
}

stack_name() {
    local sid="$1"
    aws opsworks describe-stacks --stack-id "$sid" | jq -r '.Stacks[] | .Name'
}

stack_id() {
    local name="$1"
    aws opsworks describe-stacks \
        | jq --monochrome-output --raw-output '.Stacks[] | select(.Name == "'"$name"'") | .StackId'
}

stack_ids() {
    aws opsworks describe-stacks | jq --monochrome-output --raw-output '.Stacks[] | .StackId'
}

stack_json() {
    aws opsworks describe-stacks \
        | jq '.Stacks[] | select(.CustomJson) | {StackId, Name, CustomJson: (.CustomJson | fromjson)}'
}

stack_layers() {
    local stack_name="$1"
    # shellcheck disable=SC2155
    local stack_id="$(stack_id "$stack_name")"

    aws opsworks describe-layers --stack-id "$stack_id"
}

layer_names() {
    local stack_name="$1"

    stack_layers "$stack_name" | jq --raw-output '.Layers[] | .Name'
}

layer_id() {
    local stack_name="$1"
    local layer_name="$2"
    stack_layers "$stack_name" \
        | jq -r '.Layers[] | select(.Name == "'"$layer_name"'") | .LayerId'
}

layer_instances() {
    local stack_name="$1"
    local layer_name="$2"

    aws opsworks describe-instances --layer-id "$(layer_id "$stack_name" "$layer_name")"
}

layer_instances_loader_bq() { layer_instances pipeline loader_bq; }

if [[ -z $silent_ssh_options ]]
then
    readonly silent_ssh_options=(
        -o 'ConnectTimeout=5'
        -o 'StrictHostKeyChecking=no'
        -o 'UserKnownHostsFile=/dev/null'
        -q
    )
fi

ssh_layer_instances() {
    local stack_name="$1"
    local layer_name="$2"

    layer_instances "$stack_name" "$layer_name" | \
        jq --compact-output --raw-output --monochrome-output \
           '.Instances[] | select(.PrivateIp) | @sh "ssh \(.PrivateIp) # \(.Hostname)"'
}

ssh_layer_instance() {
    local stack_name="$1"
    local layer_name="$2"
    # shellcheck disable=SC2155
    local instance="$(layer_instances "$stack_name" "$layer_name" | jq -r '[.Instances[] | select("online" == .Status)][1] | {PrivateIp, Hostname}')"

    ssh "$(jq -r '.PrivateIp' <<<"$instance")"
}

ssh_connection_service_instance() { ssh_layer_instance webservices connection_service; }

# stack: bastion
ssh_bastion_instances() { ssh_layer_instances bastion bastion; }
ssh_whitelist_tester_instances() { ssh_layer_instances bastion whitelist-tester; }

aws_bastion1_ip() {
    layer_instances bastion bastion \
        | jq -r '.Instances[] | select("bastion1" == .Hostname) | .PublicIp'
}

# stack: webservices
ssh_bastion1() { echo ssh "$(aws_bastion1_ip)" '# bastion1'; }
ssh_connection_service_instances() { ssh_layer_instances webservices connection_service; }
ssh_webhook_service_instances() { ssh_layer_instances webservices webhook_service; }
ssh_billing_service_instances() { ssh_layer_instances webservices billing_service; }
ssh_api_passthrough_instances() { ssh_layer_instances webservices api_passthrough; }
ssh_webhookz_instances() { ssh_layer_instances webservices webhookz; }
ssh_billing_service_scheduler_instances() { ssh_layer_instances webservices billing_service_scheduler; }
ssh_api_passthrough_staging_instances() { ssh_layer_instances webservices api_passthrough_staging; }
ssh_app_instances() { ssh_layer_instances webservices app; }
ssh_app_staging_instances() { ssh_layer_instances webservices app_staging; }
ssh_spool_service_instances() { ssh_layer_instances webservices spool_service; }
ssh_gate_instances() { ssh_layer_instances webservices gate; }
ssh_stats_service_instances() { ssh_layer_instances webservices stats_service; }
ssh_notification_service_instances() { ssh_layer_instances webservices notification_service; }
ssh_admin_instances() { ssh_layer_instances webservices admin; }
ssh_core_service_instances() { ssh_layer_instances webservices core_service; }
ssh_sourcerer_service_instances() { ssh_layer_instances webservices sourcerer_service; }
ssh_core_service_scheduler_instances() { ssh_layer_instances webservices core_service_scheduler; }
ssh_dbreplicators_service_instances() { ssh_layer_instances webservices dbreplicators_service; }
ssh_sourcerer_scheduler_instances() { ssh_layer_instances webservices sourcerer_scheduler; }
ssh_menagerie_instances() { ssh_layer_instances webservices menagerie; }
ssh_core_service_migrations_instances() { ssh_layer_instances webservices core_service_migrations; }

# stack: replication
ssh_sourcerer_workers_instances() { ssh_layer_instances replication sourcerer_workers; }
ssh_dbreplicators_workers_instances() { ssh_layer_instances replication dbreplicators_workers; }

# stack: monitoring
ssh_logstash_forwarder_instances() { ssh_layer_instances monitoring logstash_forwarder; }
ssh_kibana_instances() { ssh_layer_instances monitoring kibana; }
ssh_dogstatsd_instances() { ssh_layer_instances monitoring dogstatsd; }

# stack: pipeline
ssh_kafka_blue_instances() { ssh_layer_instances pipeline kafka_blue; }
ssh_kafka_green_instances() { ssh_layer_instances pipeline kafka_green; }
ssh_streamery_instances() { ssh_layer_instances pipeline streamery; }
ssh_zookeeper_instances() { ssh_layer_instances pipeline zookeeper; }
ssh_loader_snow_instances() { ssh_layer_instances pipeline loader_snow; }
ssh_loader_s3_instances() { ssh_layer_instances pipeline loader_s3; }
ssh_loader_pg_instances() { ssh_layer_instances pipeline loader_pg; }
ssh_loader_bq_instances() { ssh_layer_instances pipeline loader_bq; }
ssh_loader_x_instances() { ssh_layer_instances pipeline loader_x; }
ssh_tracer_instances() { ssh_layer_instances pipeline tracer; }

# stack: microsites
ssh_microsites_instances() { ssh_layer_instances microsites querymongo; }

ssh_instance() {
    local layer_pattern="$1"

    instance_ips | \
        grep --line-buffered "$layer_pattern" | \
            jq --compact-output --raw-output --monochrome-output \
                'select(.PrivateIp) | @sh "ssh \(.PrivateIp) # \(.Hostname)"'
}

aws_jenkins_ip() {
    layer_instances_ips deployment jenkins_master
}

ssh_jenkins_instance() {
    eval "$(ssh_layer_instances deployment jenkins_master)"
}

layer_instances_ips() {
    local stack_name="$1"
    local layer_name="$2"

    layer_instances "$stack_name" "$layer_name" | \
        jq --compact-output --raw-output --monochrome-output \
           '.Instances[] | select(.PrivateIp) | .PrivateIp'
}

create_and_start_instance() {
    local stack_name="$1"
    # shellcheck disable=SC2155
    local stack_id="$(stack_id "$stack_name")"
    local layer_name="$2"
    local instance_type="$3"

    new_instance_id="$(aws opsworks \
      create-instance \
      --stack-id "$stack_id" \
      --layer-ids "$(layer_id "$stack_id" "$layer_name")" \
      --instance-type "$instance_type" \
    | jq -r '.InstanceId')"

    aws opsworks start-instance --instance-id "$new_instance_id"
}

# left as an example for now
new_data_warehouse_service_instance() {
    create_and_start_instance primary data_warehouse_service m3.medium
}

layer_json() {
    while read -r stack_name
    do
        stack_layers "$stack_name" \
            | jq '.Layers[] | select(.CustomJson) | {StackId, Name, CustomJson: (.CustomJson | fromjson)}'
    done < <(stack_names)
}

layer_custom_recipes() {
    local stack_name="$1"
    stack_layers "$stack_name" \
        | jq '.Layers[]
          | {StackId,
             Name,
             CustomRecipes: (.CustomRecipes
                             | [.Undeploy,
                                .Setup,
                                .Configure,
                                .Shutdown,
                                .Deploy]
                             | flatten)}'
}

custom_recipes_global() {
    while read -r sn
    do
        while read -r ln
        do
            layer_custom_recipes "$sn" "$ln"
        done < <(layer_names "$sn")
    done < <(stack_names)
}

stack_instance_id() {
    local stack_id="$1"
    aws opsworks describe-instances --stack-id "$stack_id"
}

ssh_stack_instances() {
    local stack_name="$1"
    aws opsworks describe-instances --stack-id "$(stack_id "$stack_name")" \
        | jq --compact-output --raw-output --monochrome-output \
             '.Instances[] | select(.PrivateIp) | @sh "ssh \(.PrivateIp) # \(.Hostname)"'
}

stack_instances() {
    local stack_name="$1"
    aws opsworks describe-instances --stack-id "$(stack_id "$stack_name")"
}

ssh_matching_instances() {
    local stack_name="$1"
    local pattern="$2"

    ssh_stack_instances "$stack_name" | grep -F "$pattern"
}

layer_instance_exec() {
    local stack_name="$1"
    shift
    local layer_name="$1"
    shift
    # shellcheck disable=SC2155
    local instance="$(layer_instances "$stack_name" "$layer_name" | jq -r '[.Instances[] | select("online" == .Status)][1] | {PrivateIp, Hostname}')"

    if [[ --force == "$1" ]]
    then
        shift
        run_on_ip_answer=y
        echo '# Running `'"$*"'` on '"$(jq -r '.Hostname' <<<"$instance")"
    else
        read -rp '# Run `'"$*"'` on '"$(jq -r '.Hostname' <<<"$instance")? [y/N] " run_on_ip_answer
    fi

    if [[ y != "$run_on_ip_answer" ]]
    then
        echo '# Exiting at user request'
        return 0
    fi

    # shellcheck disable=SC2029
    ssh "$(jq -r '.PrivateIp' <<<"$instance")" "hostname; $*"
}

gate_instance_exec() { layer_instance_exec webservices gate; }
webhookz_instance_exec() { layer_instance_exec webservices webhookz; }

# FIXME refactor this and `multi_exec`
multi_exec_stack() {
    local stack_name="$1"
    # shellcheck disable=SC2155
    local stack_instances="$(stack_instances "$stack_name")"
    shift

    hostnames=($(jq --raw-output '.Instances[] | select("online" == .Status) | .Hostname' <<<"$stack_instances" ))

    if (( 0 == "${#hostnames[@]}" ))
    then
        echo '# No hostnames available for '"$stack_name"'. Check your creds.' >&2
        return 1
    fi

    if [[ --force == "$1" ]]
    then
        run_answer=y
        shift
        echo '# Running `'"$*"'` on the '"$stack_name"' stack:' >&2
        for hn in "${hostnames[@]}"
        do
            echo "# $hn" >&2
        done
    else
        echo '# Run `'"$*"'` on the '"$stack_name"' stack?'
        for hn in "${hostnames[@]}"
        do
            echo "# $hn"
        done
        read -rp "# [y/N] " run_answer
    fi

    if [[ $run_answer != "y" ]]
    then
        echo '# Not running'
        return 0
    fi

    hostips=($(jq --raw-output '.Instances[] | select(.Hostname | contains("'"$pattern"'")) | select(.PrivateIp) | .PrivateIp' <<<"$stack_instances"))

    parallel -j 0 "ssh '{}' 'hostname; $*'" ::: "${hostips[@]}"
}

multi_exec_bastion() { multi_exec_stack bastion; }
multi_exec_webservices() { multi_exec_stack webservices; }
multi_exec_replication() { multi_exec_stack replication; }
multi_exec_monitoring() { multi_exec_stack monitoring; }
multi_exec_pipeline() { multi_exec_stack pipeline; }
multi_exec_microsites() { multi_exec_stack microsites; }

# FIXME refactor this and `multi_exec`
multi_exec_global() {
    global_instances="$(instances)"

    hostnames=($(jq --raw-output 'select("online" == .Status) | .Hostname' <<<"$global_instances" ))

    if (( 0 == "${#hostnames[@]}" ))
    then
        echo '# No hostnames available globally. Check your creds.' >&2
        return 1
    fi

    if [[ --force == "$1" ]]
    then
        run_answer=y
        shift
        echo '# Running `'"$*"'` globally on:'
        for hn in "${hostnames[@]}"
        do
            echo "# $hn"
        done
    else
        echo '# Run `'"$*"'` globally on:'
        for hn in "${hostnames[@]}"
        do
            echo "# $hn"
        done
        read -rp "# ? [y/N] " run_answer
    fi

    if [[ $run_answer != "y" ]]
    then
        echo '# Not running'
        return 0
    fi

    hostips=($(jq --raw-output 'select("online" == .Status) | select(.Hostname | contains("'"$pattern"'")) | select(.PrivateIp) | .PrivateIp' <<<"$global_instances"))

    parallel -j 0 "ssh '{}' 'hostname; $*'" ::: "${hostips[@]}"
}

# FIXME refactor this and `multi_exec`
multi_exec_layer() {
    local stack_name="$1"
    shift
    local layer_name="$1"
    # shellcheck disable=SC2155
    local layer_instances="$(layer_instances "$stack_name" "$layer_name")"
    shift

    hostnames=($(jq --raw-output '.Instances[] | select("online" == .Status) | .Hostname' <<<"$layer_instances" ))

    if (( 0 == "${#hostnames[@]}" ))
    then
        echo '# No hostnames available for '"$layer_name"'. Check your creds.' >&2
        return 1
    fi

    if [[ --force == "$1" ]]
    then
        run_answer=y
        shift
        echo '# Running `'"$*"'` on the '"$layer_name"' layer:'
        for hn in "${hostnames[@]}"
        do
            echo "# $hn"
        done
    else
        echo '# Run `'"$*"'` on the '"$layer_name"' layer?'
        for hn in "${hostnames[@]}"
        do
            echo "# $hn"
        done
        read -rp "# [y/N] " run_answer
    fi

    if [[ $run_answer != "y" ]]
    then
        echo '# Not running'
        return 0
    fi

    hostips=($(jq --raw-output '.Instances[] | select("online" == .Status) | select(.Hostname | contains("'"$pattern"'")) | select(.PrivateIp) | .PrivateIp' <<<"$layer_instances"))

    parallel -j 0 "ssh '{}' 'hostname; $*'" ::: "${hostips[@]}"
}

# stack: bastion
multi_exec_bastion() { multi_exec_layer bastion bastion "$@"; }
multi_exec_whitelist_tester() { multi_exec_layer bastion whitelist-tester "$@"; }

# stack: webservices
multi_exec_connection_service() { multi_exec_layer webservices connection_service "$@"; }
multi_exec_webhook_service() { multi_exec_layer webservices webhook_service "$@"; }
multi_exec_billing_service() { multi_exec_layer webservices billing_service "$@"; }
multi_exec_api_passthrough() { multi_exec_layer webservices api_passthrough "$@"; }
multi_exec_webhookz() { multi_exec_layer webservices webhookz "$@"; }
multi_exec_billing_service_scheduler() { multi_exec_layer webservices billing_service_scheduler "$@"; }
multi_exec_api_passthrough_staging() { multi_exec_layer webservices api_passthrough_staging "$@"; }
multi_exec_app() { multi_exec_layer webservices app "$@"; }
multi_exec_app_staging() { multi_exec_layer webservices app_staging "$@"; }
multi_exec_spool_service() { multi_exec_layer webservices spool_service "$@"; }
multi_exec_gate() { multi_exec_layer webservices gate "$@"; }
multi_exec_stats_service() { multi_exec_layer webservices stats_service "$@"; }
multi_exec_notification_service() { multi_exec_layer webservices notification_service "$@"; }
multi_exec_admin() { multi_exec_layer webservices admin "$@"; }
multi_exec_core_service() { multi_exec_layer webservices core_service "$@"; }
multi_exec_sourcerer_service() { multi_exec_layer webservices sourcerer_service "$@"; }
multi_exec_core_service_scheduler() { multi_exec_layer webservices core_service_scheduler "$@"; }
multi_exec_dbreplicators_service() { multi_exec_layer webservices dbreplicators_service "$@"; }
multi_exec_sourcerer_scheduler() { multi_exec_layer webservices sourcerer_scheduler "$@"; }
multi_exec_menagerie() { multi_exec_layer webservices menagerie "$@"; }
multi_exec_core_service_migrations() { multi_exec_layer webservices core_service_migrations "$@"; }

# stack: replication
multi_exec_sourcerer_workers() { multi_exec_layer replication sourcerer_workers "$@"; }
multi_exec_dbreplicators_workers() { multi_exec_layer replication dbreplicators_workers "$@"; }

# stack: monitoring
multi_exec_logstash_forwarder() { multi_exec_layer monitoring logstash_forwarder "$@"; }
multi_exec_kibana() { multi_exec_layer monitoring kibana "$@"; }
multi_exec_dogstatsd() { multi_exec_layer monitoring dogstatsd "$@"; }

# stack: pipeline
multi_exec_kafka_blue() { multi_exec_layer pipeline kafka_blue "$@"; }
multi_exec_kafka_green() { multi_exec_layer pipeline kafka_green "$@"; }
multi_exec_streamery() { multi_exec_layer pipeline streamery "$@"; }
multi_exec_zookeeper() { multi_exec_layer pipeline zookeeper "$@"; }
multi_exec_loader_pg() { multi_exec_layer pipeline loader_pg "$@"; }
multi_exec_loader_bq() { multi_exec_layer pipeline loader_bq "$@"; }
multi_exec_loader_x() { multi_exec_layer pipeline loader_x "$@"; }
multi_exec_tracer() { multi_exec_layer pipeline tracer "$@"; }

# stack: microsites
multi_exec_microsites() { multi_exec_layer microsites querymongo; }

# FIXME refactor this and `multi_exec_layer`
multi_exec() {
    local stack_name="$1"
    # shellcheck disable=SC2155
    local stack_instances="$(stack_instances "$stack_name")"
    shift
    local pattern="$1"
    shift

    hostnames=($(jq --raw-output '.Instances[] | .Hostname | select(test("'"$pattern"'"))' <<<"$stack_instances"))

    if (( 0 == "${#hostnames[@]}" ))
    then
        echo '# No hostnames available for '"$pattern"'. Check your creds.' >&2
        return 1
    fi

    if [[ --force == "$1" ]]
    then
        run_answer=y
        shift
        echo '# Running `'"$*"'` on the following hosts?'
        for hn in "${hostnames[@]}"
        do
            echo "# $hn"
        done
    else
        echo '# Run `'"$*"'` on the following hosts?'
        for hn in "${hostnames[@]}"
        do
            echo "# $hn"
        done
        read -rp "# [y/N] " run_answer
    fi

    if [[ $run_answer != "y" ]]
    then
        echo '# Not running'
        return 0
    fi

    hostips=($(jq --raw-output '.Instances[] | select(.Hostname | test("'"$pattern"'")) | select(.PrivateIp) | .PrivateIp' <<<"$stack_instances"))

    parallel -j 0 "ssh '{}' 'hostname; $*'" ::: "${hostips[@]}"
}

instance_id() {
    local stack_id="$1"
    local instance_hostname="$2"

    aws opsworks describe-instances --stack-id "$stack_id" \
        | jq -r '.Instances[] | select(.Hostname == "'"$instance_hostname"'") | .InstanceId'
}

stop_instance() {
    # shellcheck disable=SC2155
    local stack_id="$(stack_id "$1")"
    # shellcheck disable=SC2155
    local instance_id="$(instance_id "$stack_id" "$2")"

    aws opsworks stop-instance --instance-id "$instance_id"
}

instances() {
    while read -r stack_id
    do
        aws opsworks describe-instances --stack-id="$stack_id" | jq '.Instances[]'
    done < <(stack_ids)
}

instance_ips() {
    for stack_id in $(stack_ids)
    do
        aws opsworks describe-instances --stack-id="$stack_id" \
            | jq --compact-output '.Instances[] | select(.PrivateIp) | {Hostname, PrivateIp, StackId, Ec2InstanceId}'
    done \
        | sort
}

##########################################################################
### aws role management
##########################################################################

_pp_role_cache_file() {
    local role_cache_file="$1"
    if [[ -r "$role_cache_file" ]]
    then
        expiration="$(jq -r '.Credentials.Expiration' < "$role_cache_file")"
        if [[ -n $expiration ]]
        then
            if [[ $(mins_until_expired "$expiration") != -* ]]
            then
                echo "assume_${role_cache_file##*\.} 123456 # $(mins_until_expired "$(jq -r '.Credentials.Expiration' < "$role_cache_file")")m"
            fi
        else
            tput setaf 1
            tput bold
            echo "# Bad role cache file: $role_cache_file" >&2
            local role_cache_file_dir="${role_cache_file%/*}"
            local role_cache_file_name="${role_cache_file##*/}"
            mv -v "$role_cache_file" "${role_cache_file_dir}/bad.${role_cache_file_name}"
            tput sgr0
            return 1
        fi
    else
        echo '# No role cache' >&2
    fi
}

pp_role_caches() {
    local cache_file
    for cache_file in ~/.stitch/assume-role-cache.*
    do
        _pp_role_cache_file "$cache_file"
    done
}

gnu_date_command() {
    local target="$1"

    date -d "$target" +'%s'
}

bsd_date_command() {
    local target="$1"

    date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$target" '+%s'
}

determine_date_flavor() {
    if [[ -n $date_flavor ]]
    then
        return 0
    elif bsd_date_command "${AWS_ROLE_EXPIRATION:-2016-11-01T11:23:13Z}" > /dev/null 2>&1
    then
        date_flavor=bsd
    elif gnu_date_command "${AWS_ROLE_EXPIRATION:-2016-11-01T11:23:13Z}" > /dev/null 2>&1
    then
        date_flavor=gnu
    fi
}

mins_until_expired() {
    local input_date="$1"
    determine_date_flavor

    if [[ $date_flavor == bsd ]]
    then
        # shellcheck disable=SC2155
        local target="$(bsd_date_command "$input_date")"
    elif [[ $date_flavor == gnu ]]
    then
        # shellcheck disable=SC2155
        local target="$(gnu_date_command "$input_date")"
    else
        echo '# Unable to determine your date flavor.' >&2
        return 1
    fi

    # shellcheck disable=SC2155
    local now="$(date '+%s')"
    echo "$(((target - now)/60))"
}

export_aws_vars() {
    role_name="$1"

    if [[ -z $role_name ]]
    then
        echo '# Usage: export_aws_vars role_name' >&2
        return 1
    fi

    if [[ ! -r ~/.stitch/assume-role-cache."$role_name" ]]
    then
        echo '# Run shell_init_role' >&2
        return 1
    fi

    # shellcheck disable=SC2155
    export AWS_ROLE_NAME="$role_name"
    # shellcheck disable=SC2155
    export AWS_ACCESS_KEY_ID="$(jq -r '.Credentials.AccessKeyId' < ~/.stitch/assume-role-cache."$AWS_ROLE_NAME")"
    # shellcheck disable=SC2155
    export AWS_SECRET_ACCESS_KEY="$(jq -r '.Credentials.SecretAccessKey' < ~/.stitch/assume-role-cache."$AWS_ROLE_NAME")"
    # shellcheck disable=SC2155
    export AWS_SESSION_TOKEN="$(jq -r '.Credentials.SessionToken' < ~/.stitch/assume-role-cache."$AWS_ROLE_NAME")"
    # shellcheck disable=SC2155
    export AWS_ROLE_EXPIRATION="$(jq -r '.Credentials.Expiration' < ~/.stitch/assume-role-cache."$AWS_ROLE_NAME")"

    if ! mins_until_expired "$AWS_ROLE_EXPIRATION" > /dev/null 2>&1
    then
        echo '# Unable to run mins_until_expired. exporting was not successful.' >&2
        unexport_aws_vars
        return 1
    fi

    # FIXME we need a way to generate a PS1 template
    export PS1='\n\d \t\n\u@\H\n[$AWS_ROLE_NAME:$(mins_until_expired "$AWS_ROLE_EXPIRATION")m]\n\w$(__git_ps1)\n\$ '
}

alias unexport_aws_vars=unassume_role

shell_init_usage() {
    echo '# Usage: shell_init_role role_name mfa_token' >&2
}

role_expired() {
    local role_name="$1"
    # role cache doesn't exist so we're 'expired'
    if [[ ! -r ~/.stitch/assume-role-cache."$role_name" ]]
    then
        return 0
    # less than 1 minutes left
    elif (( 1 > $(mins_until_expired "$(jq -r '.Credentials.Expiration' < ~/.stitch/assume-role-cache."$role_name")") ))
    then
        return 0
    else
        return 1
    fi
}

shell_init_role() {
    local role_name="$1"
    local mfa_token="$2"

    if [[ -z $role_name || -z $mfa_token ]]
    then
        shell_init_usage
        return 1
    fi

    if ! grep -qF "[profile $role_name]" ~/.aws/config
    then
        echo "$(tput setaf 1)$(tput bold)# Unable to find AWS profile $role_name.$(tput sgr0)"
        echo "$(tput setaf 1)$(tput bold)# Run:$(tput sgr0)"
        echo "$(tput setaf 1)$(tput bold)configure_aws_profiles$(tput sgr0)"
        return 1
    fi

    mkdir -p ~/.stitch

    if role_expired "$role_name"
    then
        if ! aws --profile "$(aws --profile "$role_name" configure get source_profile)" \
             sts assume-role \
             --role-arn "$(aws --profile "$role_name" configure get role_arn)" \
             --serial-number "$(aws --profile "$role_name" configure get mfa_serial)" \
             --role-session-name vm.cli.user-"$LOGNAME" \
             --token-code "$mfa_token" > ~/.stitch/assume-role-cache."$role_name"
        then
            echo '# Failed to fetch the role cache from aws.' >&2
            return 1
        fi
    fi

    echo "$role_name" > ~/.stitch/aws-role-name-cache

    export_aws_vars "$role_name"
}

unassume_role() {
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    unset AWS_ROLE_EXPIRATION
    unset AWS_ROLE_NAME
    export PS1="$DEFAULT_PS1"
}

assume_read_only() { shell_init_role read_only "$@"; }
aro() { assume_read_only "$@"; }
assume_admin_global() { shell_init_role admin_global "$@"; }
aag() { assume_admin_global "$@"; }

uncache_role() {
    local role_name="$1"

    if [[ -z $role_name ]]
    then
        echo "$(tput setaf 1)$(tput bold)# No role name specified$(tput sgr0)"
        return 1
    fi

    if [[ -r ~/.stitch/assume-role-cache."$role_name" ]]
    then
        rm -v ~/.stitch/assume-role-cache."$role_name"
    fi
}

uncache_read_only() { uncache_role read_only; }
uncache_admin_global() { uncache_role admin_global; }

set_default_profile() {
    if aws --profile "$1" configure get role_arn > /dev/null 2>&1
    then
        export AWS_DEFAULT_PROFILE="$1"
        export PS1='\n\d \t\n\u@\H\n[default profile: $AWS_DEFAULT_PROFILE]\n\w$(__git_ps1)\n\$ '
    else
        echo "# Profile $1 is not configured" >&2
    fi
}

unset_default_profile() {
    unset AWS_DEFAULT_PROFILE
    export PS1="$DEFAULT_PS1"
}

configure_aws_profiles() {
    if ! aws configure get aws_access_key_id > /dev/null 2>&1 || ! aws configure get aws_secret_access_key > /dev/null 2>&1
    then
        echo '# Configure your default (stitch-prod) profile.' >&2
        echo 'aws configure' >&2
        return 1
    fi

    # good to try to grab the default user

    mkdir -p ~/.stitch/

    if ! aws iam get-user > ~/.stitch/aws-default-user-cache 2>/dev/null
    then
        echo '# Unable to retrieve the user associated with the default profile. Please check your keys.' >&2
        return 1
    fi

    # good to generate the template

    local user_name
    user_name="$(jq -r '.User.UserName' < ~/.stitch/aws-default-user-cache)"

    # admin_global
    aws --profile admin_global configure set role_arn 'arn:aws:iam::218546966473:role/admin_global'
    aws --profile admin_global configure set source_profile default
    aws --profile admin_global configure set mfa_serial "arn:aws:iam::218546966473:mfa/$user_name"

    # read_only
    aws --profile read_only configure set role_arn 'arn:aws:iam::218546966473:role/read_only'
    aws --profile read_only configure set source_profile default
    aws --profile read_only configure set mfa_serial "arn:aws:iam::218546966473:mfa/$user_name"

}

export_profile_key() {
    local profile_name="$1"

    if ! aws configure get aws_access_key_id --profile "$profile_name" >/dev/null 2>&1 || ! aws configure get aws_secret_access_key --profile "$profile_name" >/dev/null 2>&1
    then
        echo "# Couldn't find key pair for $profile_name" >&2
        return 1
    fi

    # shellcheck disable=SC2155
    export AWS_ACCESS_KEY_ID="$(aws configure get aws_access_key_id --profile "$profile_name")"
    # shellcheck disable=SC2155
    export AWS_SECRET_ACCESS_KEY="$(aws configure get aws_secret_access_key --profile "$profile_name")"

    echo "# AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID"
    echo "# AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY"
}

_assert_role_show_help() {
    cat <<EOF
assert_role <admin_global|read_only>
EOF
}

assert_role() {
    local role_name=$1

    if [[ $role_name != +(admin_global|read_only) ]]
    then
        _assert_role_show_help
        return 1
    fi

    if [[ $role_name != $AWS_ROLE_NAME ]]
    then
        echo "${role_name} != \$AWS_ROLE_NAME (${AWS_ROLE_NAME:-<unset>})" >&2
        return 1
    fi
    local expiration=$(mins_until_expired "${AWS_ROLE_EXPIRATION:-2016-11-01T11:23:13Z}")
    if (( $expiration <= 0 ))
    then
        echo "${expiration} <= 0"
        return 1
    fi
}

assert_admin_global() {
    assert_role admin_global
}

assert_read_only() {
    assert_role read_only
}

##########################################################################
### nrepl
##########################################################################

nrepl_menagerie() {
    # shellcheck disable=SC2155
    local instance="$(layer_instances "webservices" "menagerie" | jq -r '[.Instances[] | select("online" == .Status)][1] | {PrivateIp, Hostname}')"
    # shellcheck disable=SC2155
    local ip="$(jq -r '.PrivateIp' <<<"$instance")"
    # shellcheck disable=SC2155
    local hostname="$(jq -r '.Hostname' <<<"$instance")"
    command=(ssh -L6033:localhost:4033 "$ip")
    echo "# ${command[*]}" >&2
    ${command[*]}
}

##########################################################################
### Deployment Monitoring
##########################################################################

aws_stack_status() {
    local stack_name=$1

    stack_instances "$stack_name" \
        | jq -r '.Instances[] | "\(.Hostname) (\(.PrivateIp)): \(.Status)"' \
        | sort -n
}

aws_stack_status_monitoring() { aws_stack_status monitoring; }
aws_stack_status_bastion() { aws_stack_status bastion; }
aws_stack_status_webservices() { aws_stack_status webservices; }
aws_stack_status_replication() { aws_stack_status replication; }
aws_stack_status_monitoring() { aws_stack_status monitoring; }
aws_stack_status_pipeline() { aws_stack_status pipeline; }
aws_stack_status_microsites() { aws_stack_status microsites; }
aws_stack_status_deployment() { aws_stack_status deployment; }

##########################################################################
### aws_layer_status
###
### Useful for watching a deploy like:
###
### Quotes Necessary!
### watch -d -n 10 'bash -lc "aws_layer_status foo bar"'
##########################################################################
aws_layer_status() {
    local stack_name=$1
    local layer_name=$2

    layer_instances "$stack_name" "$layer_name" \
        | jq -r '.Instances[] | "\(.Hostname) (\(.PrivateIp)): \(.Status)"' \
        | sort -n
}

aws_layer_status_admin() { aws_layer_status webservices admin; }
aws_layer_status_api_passthrough() { aws_layer_status webservices api_passthrough; }
aws_layer_status_api_passthrough_staging() { aws_layer_status webservices api_passthrough_staging; }
aws_layer_status_bastion() { aws_layer_status bastion bastion; }
aws_layer_status_billing_service() { aws_layer_status webservices billing_service; }
aws_layer_status_billing_service_scheduler() { aws_layer_status webservices billing_service_scheduler; }
aws_layer_status_connection_service() { aws_layer_status webservices connection_service; }
aws_layer_status_core_service() { aws_layer_status webservices core_service; }
aws_layer_status_core_service_migrations() { aws_layer_status webservices core_service_migrations; }
aws_layer_status_core_service_scheduler() { aws_layer_status webservices core_service_scheduler; }
aws_layer_status_dbreplicators_service() { aws_layer_status webservices dbreplicators_service; }
aws_layer_status_dbreplicators_workers() { aws_layer_status replication dbreplicators_workers; }
aws_layer_status_dogstatsd() { aws_layer_status monitoring dogstatsd; }
aws_layer_status_elastalert() { aws_layer_status monitoring elastalert; }
aws_layer_status_elasticsearch_forwarder() { aws_layer_status monitoring elasticsearch_forwarder; }
aws_layer_status_front_end_app() { aws_layer_status webservices front_end_app; }
aws_layer_status_front_end_app_staging() { aws_layer_status webservices front_end_app_staging; }
aws_layer_status_gate() { aws_layer_status webservices gate; }
aws_layer_status_jenkins_master() { aws_layer_status deployment jenkins_master; }
aws_layer_status_kafka_blue() { aws_layer_status pipeline kafka_blue; }
aws_layer_status_kafka_green() { aws_layer_status pipeline kafka_green; }
aws_layer_status_kibana() { aws_layer_status monitoring kibana; }
aws_layer_status_loader_bq() { aws_layer_status pipeline loader_bq; }
aws_layer_status_loader_pg() { aws_layer_status pipeline loader_pg; }
aws_layer_status_loader_snow() { aws_layer_status pipeline loader_snow; }
aws_layer_status_loader_x() { aws_layer_status pipeline loader_x; }
aws_layer_status_logstash_forwarder() { aws_layer_status monitoring logstash_forwarder; }
aws_layer_status_menagerie() { aws_layer_status webservices menagerie; }
aws_layer_status_notification_service() { aws_layer_status webservices notification_service; }
aws_layer_status_querymongo() { aws_layer_status microsites querymongo; }
aws_layer_status_sourcerer_scheduler() { aws_layer_status webservices sourcerer_scheduler; }
aws_layer_status_sourcerer_service() { aws_layer_status webservices sourcerer_service; }
aws_layer_status_sourcerer_workers() { aws_layer_status replication sourcerer_workers; }
aws_layer_status_spool_service() { aws_layer_status webservices spool_service; }
aws_layer_status_stats_service() { aws_layer_status webservices stats_service; }
aws_layer_status_streamery() { aws_layer_status pipeline streamery; }
aws_layer_status_tracer() { aws_layer_status pipeline tracer; }
aws_layer_status_webhook_service() { aws_layer_status webservices webhook_service; }
aws_layer_status_webhookz() { aws_layer_status webservices webhookz; }
aws_layer_status_whitelist_tester() { aws_layer_status bastion whitelist-tester; }
aws_layer_status_zookeeper() { aws_layer_status pipeline zookeeper; }

# ELB

aws_elb_names() {
    aws elb describe-load-balancers \
        | jq -r '.LoadBalancerDescriptions[] | .LoadBalancerName'
}

_aws_elb_describe() {
    local -a elb_names=("$@")

    aws elb describe-load-balancers --load-balancer-names "${elb_names[@]}" \
        | jq -r '.LoadBalancerDescriptions[]'
}

_aws_elb_instance_ids() {
    local -a elb_names=("$@")

    # shellcheck disable=SC2155
    local aws_elb_json="$(_aws_elb_describe "${elb_names[@]}")"

    jq -r '.Instances[] | .InstanceId' <<< "$aws_elb_json"
}

_aws_ec2_describe_instances() {
    local -a ec2_instance_ids=("$@")

    aws ec2 describe-instances --instance-ids "${ec2_instance_ids[@]}" \
        | jq -r '.Reservations[] | .Instances[]'
}

_aws_elb_describe_instances() {
    local -a elb_names=("$@")

    # word splitting is desirable here
    # shellcheck disable=SC2046
    _aws_ec2_describe_instances $(_aws_elb_instance_ids "${elb_names[@]}")
}

_aws_elb_describe_instance_health() {
    local -a elb_names=("$@")

    local elb_name
    for elb_name in "${elb_names[@]}"
    do
        aws elb describe-instance-health --load-balancer-name "$elb_name" \
            | jq -r '.InstanceStates[]'
    done
}

aws_elb_instance_health() {
    local -a elb_names=("$@")

    # shellcheck disable=SC2155
    local instances_json=$(_aws_elb_describe_instances "${elb_names[@]}")
    # shellcheck disable=SC2155
    local -a instance_ids=($(_aws_elb_instance_ids "${elb_names[@]}"))
    # shellcheck disable=SC2155
    local health_json=$(_aws_elb_describe_instance_health "${elb_names[@]}")

    for instance_id in "${instance_ids[@]}"
    do
        # shellcheck disable=SC2155
        local hostname="$(jq -r 'select("'"$instance_id"'" == .InstanceId)
                                 | .Tags[]
                                 |  select("opsworks:instance" == .Key)
                                 | .Value' <<< "$instances_json")"
        # shellcheck disable=SC2155
        local health="$(jq -r 'select("'"$instance_id"'" == .InstanceId)
                               | .State' <<< "$health_json")"
        echo "$hostname: $health"
    done
}

aws_elb_instance_health_admin() { aws_elb_instance_health admin; }
aws_elb_instance_health_api_passthrough() { aws_elb_instance_health api-passthrough; }
aws_elb_instance_health_api_passthrough_staging() { aws_elb_instance_health api-passthrough-staging; }
aws_elb_instance_health_billing_service() { aws_elb_instance_health billing-service; }
aws_elb_instance_health_connection_service() { aws_elb_instance_health connection-service; }
aws_elb_instance_health_core_service() { aws_elb_instance_health core-service; }
aws_elb_instance_health_dbreplicators_service() { aws_elb_instance_health dbreplicators-service; }
aws_elb_instance_health_elasticsearch_forwarder() { aws_elb_instance_health elasticsearch-forwarder; }
aws_elb_instance_health_front_end_app() { aws_elb_instance_health front-end-app; }
aws_elb_instance_health_front_end_app_staging() { aws_elb_instance_health front-end-app-staging; }
aws_elb_instance_health_gate() { aws_elb_instance_health gate; }
aws_elb_instance_health_jenkins_stitchdata_com() { aws_elb_instance_health jenkins-stitchdata-com; }
aws_elb_instance_health_kibana() { aws_elb_instance_health kibana; }
aws_elb_instance_health_logstash_forwarder() { aws_elb_instance_health logstash-forwarder; }
aws_elb_instance_health_menagerie() { aws_elb_instance_health menagerie; }
aws_elb_instance_health_notification_service() { aws_elb_instance_health notification-service; }
aws_elb_instance_health_querymongo() { aws_elb_instance_health querymongo; }
aws_elb_instance_health_sourcerer_service() { aws_elb_instance_health sourcerer-service; }
aws_elb_instance_health_spool_service() { aws_elb_instance_health spool-service; }
aws_elb_instance_health_stats_service() { aws_elb_instance_health stats-service; }
aws_elb_instance_health_webhookz() { aws_elb_instance_health webhookz; }

# FIXME provide a way to detect age of boxes and force restart
# while read -r stack_id; do aws opsworks describe-instances --stack-id "$stack_id"; done < <(stack_ids) | jq '.Instances[]' | jq --slurp --compact-output 'sort_by(.CreatedAt)[] | {Hostname, CreatedAt}'

##########################################################################
### autoscaling
##########################################################################

_aws_as_describe_groups() {
    # FIXME does this handle no arg?
    aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "${group_names[@]}" \
        | jq '.AutoScalingGroups[]'
}

aws_as_describe_groups_instances() {
    local group_names=("$@")

    # word splitting is desirable here
    # shellcheck disable=SC2046
    _aws_ec2_describe_instances $(aws autoscaling \
                                      describe-auto-scaling-instances \
                                      --instance-ids $(_aws_as_describe_groups "${group_names[@]}" \
                                                           | jq -r '.Instances[] | .InstanceId') \
                                      | jq -r '.AutoScalingInstances[] | .InstanceId')
}

aws_as_describe_instances() {
    local instance_ids=("${@}")

    # word splitting is desirable here
    # shellcheck disable=SC2046
    local as_instances=$(aws autoscaling describe-auto-scaling-instances --instance-ids "${instance_ids[@]}" \
                             | jq -r '.AutoScalingInstances[] | .InstanceId')
    if [[ -z $as_instances ]]
    then
        echo "# No matching instances for ids: ${instance_ids[@]}" >&2
        return 1
    fi
    _aws_ec2_describe_instances $as_instances
}

aws_as_terminate_instance() {
    local instance_id=$1

    if aws autoscaling terminate-instance-in-auto-scaling-group \
           --instance-id "$instance_id" \
           --no-should-decrement-desired-capacity
    then
        echo "Terminated ${instance_id}"
    else
        echo "Failed to terminate ${instance_id}"
        return 1
    fi
}

##########################################################################
### security groups
##########################################################################

aws_sg_list() {
    aws_sg_list | jq -r '[.SecurityGroups[] | [.GroupName,.GroupId]] | sort_by(0)[] | @tsv' | column -t -s $'\t'
}
