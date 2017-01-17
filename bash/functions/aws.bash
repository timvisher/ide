# shellcheck shell=bash

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

ssh_layer_instances() {
    local stack_name="$1"
    local layer_name="$2"

    layer_instances "$stack_name" "$layer_name" | \
        jq --compact-output --raw-output --monochrome-output \
           '.Instances[] | select(.PrivateIp) | @sh "ssh \(.PrivateIp) # \(.Hostname)"'
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
    for stack_id in $(stack_ids)
    do
        stack_layers "$stack_id" \
            | jq '.Layers[] | select(.CustomJson) | {StackId, Name, CustomJson: (.CustomJson | fromjson)}'
    done
}

layer_custom_recipes() {
    local stack_id="$1"
    stack_layers "$stack_id" \
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
    local instance="$(layer_instances "$stack_name" "$layer_name" | jq -r '.Instances[1] | {PrivateIp, Hostname}')"

    if [[ --force == $1 ]]
    then
        shift
        run_on_ip_answer=y
        echo '# Running `'"$*"'` on '"$(jq -r '.Hostname' <<<"$instance")"
    else
        read -rp '# Run `'"$*"'` on '"$(jq -r '.Hostname' <<<"$instance")? [y/N] " run_on_ip_answer
    fi

    if [[ y != $run_on_ip_answer ]]
    then
        echo '# Exiting at user request'
        return 0
    fi

    ssh -o StrictHostKeyChecking=no "$(jq -r '.PrivateIp' <<<"$instance")" "hostname; $*"
}

# FIXME refactor this and `multi_exec`
multi_exec_layer() {
    local stack_name="$1"
    shift
    local layer_name="$1"
    local layer_instances="$(layer_instances "$stack_name" "$layer_name")"
    shift

    hostnames=($(jq --raw-output '.Instances[] | .Hostname' <<<"$layer_instances" ))

    if [[ -z $hostnames ]]
    then
        echo '# No hostnames available for '"$layer_name"'. Check your creds.' >&2
        return 1
    fi

    if [[ --force == $1 ]]
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

    hostips=($(jq --raw-output '.Instances[] | select(.Hostname | contains("'"$pattern"'")) | select(.PrivateIp) | .PrivateIp' <<<"$layer_instances"))

    parallel "ssh -o StrictHostKeyChecking=no '{}' 'hostname; $*'" ::: "${hostips[@]}"
}

# FIXME refactor this and `multi_exec_layer`
multi_exec() {
    local stack_name="$1"
    local stack_instances="$(stack_instances "$stack_name")"
    shift
    local pattern="$1"
    shift

    hostnames=($(jq --raw-output '.Instances[] | .Hostname | select(test("'"$pattern"'"))' <<<"$stack_instances"))

    if [[ -z $hostnames ]]
    then
        echo '# No hostnames available for '"$pattern"'. Check your creds.' >&2
        return 1
    fi

    if [[ --force == $1 ]]
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

    parallel "ssh -o StrictHostKeyChecking=no '{}' 'hostname; $*'" ::: "${hostips[@]}"
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

instance_ips() {
    for stack_id in $(stack_ids)
    do
        aws opsworks describe-instances --stack-id="$stack_id" \
            | jq --compact-output '.Instances[] | select(.PrivateIp) | {Hostname, PrivateIp, StackId, Ec2InstanceId}'
    done \
        | sort
}

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

alias assume_dev_admin_global='shell_init_role dev_admin_global'
alias assume_prod_admin='shell_init_role prod_admin'
alias assume_prod_admin_global='shell_init_role prod_admin_global'
alias assume_prod_read_only='shell_init_role prod_read_only'
alias assume_stitch_dev_read_only='shell_init_role stitch_dev_read_only'
alias assume_stitch_dev_admin_global='shell_init_role stitch_dev_admin_global'
alias assume_stitch_prod_read_only='shell_init_role stitch_prod_read_only'
alias assume_stitch_prod_admin='shell_init_role stitch_prod_admin'
alias assume_stitch_prod_admin_global='shell_init_role stitch_prod_admin_global'
alias assume_read_only='shell_init_role read_only'
alias assume_poweruser='shell_init_role poweruser'
alias assume_admin_global='shell_init_role admin_global'

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
    if ! aws --profile iam configure get aws_access_key_id > /dev/null 2>&1 || ! aws --profile iam configure get aws_secret_access_key > /dev/null 2>&1
    then
        echo '# Configure your iam profile.' >&2
        echo 'aws --profile iam configure' >&2
        return 1
    fi

    # good to try to grab the iam user

    mkdir -p ~/.stitch/

    if ! aws --profile iam iam get-user > ~/.stitch/aws-iam-user-cache 2>/dev/null
    then
        echo '# Unable to retrieve the user associated with the iam profile. Please check your keys.' >&2
        return 1
    fi

    # good to generate the template

    local user_name
    user_name="$(jq -r '.User.UserName' < ~/.stitch/aws-iam-user-cache)"

    # dev_admin_global
    aws --profile dev_admin_global configure set role_arn 'arn:aws:iam::718988833002:role/dev_admin_global'
    aws --profile dev_admin_global configure set source_profile iam
    aws --profile dev_admin_global configure set mfa_serial "arn:aws:iam::240342446256:mfa/$user_name"

    # prod_admin
    aws --profile prod_admin configure set role_arn 'arn:aws:iam::618319395214:role/prod_admin'
    aws --profile prod_admin configure set source_profile iam
    aws --profile prod_admin configure set mfa_serial "arn:aws:iam::240342446256:mfa/$user_name"

    # prod_admin_global
    aws --profile prod_admin_global configure set role_arn 'arn:aws:iam::618319395214:role/prod_admin_global'
    aws --profile prod_admin_global configure set source_profile iam
    aws --profile prod_admin_global configure set mfa_serial "arn:aws:iam::240342446256:mfa/$user_name"

    # prod_read_only
    aws --profile prod_read_only configure set role_arn 'arn:aws:iam::618319395214:role/prod_read_only'
    aws --profile prod_read_only configure set source_profile iam
    aws --profile prod_read_only configure set mfa_serial "arn:aws:iam::240342446256:mfa/$user_name"

    # stitch_dev_read_only
    aws --profile stitch_dev_read_only configure set role_arn 'arn:aws:iam::286131424992:role/stitch_dev_read_only'
    aws --profile stitch_dev_read_only configure set source_profile iam
    aws --profile stitch_dev_read_only configure set mfa_serial "arn:aws:iam::240342446256:mfa/$user_name"

    # stitch_dev_admin_global
    aws --profile stitch_dev_admin_global configure set role_arn 'arn:aws:iam::286131424992:role/stitch_dev_admin_global'
    aws --profile stitch_dev_admin_global configure set source_profile iam
    aws --profile stitch_dev_admin_global configure set mfa_serial "arn:aws:iam::240342446256:mfa/$user_name"

    # stitch_prod_read_only
    aws --profile stitch_prod_read_only configure set role_arn 'arn:aws:iam::218546966473:role/stitch_prod_read_only'
    aws --profile stitch_prod_read_only configure set source_profile iam
    aws --profile stitch_prod_read_only configure set mfa_serial "arn:aws:iam::240342446256:mfa/$user_name"

    # stitch_prod_admin
    aws --profile stitch_prod_admin configure set role_arn 'arn:aws:iam::218546966473:role/stitch_prod_admin'
    aws --profile stitch_prod_admin configure set source_profile iam
    aws --profile stitch_prod_admin configure set mfa_serial "arn:aws:iam::240342446256:mfa/$user_name"

    # stitch_prod_admin_global
    aws --profile stitch_prod_admin_global configure set role_arn 'arn:aws:iam::218546966473:role/stitch_prod_admin_global'
    aws --profile stitch_prod_admin_global configure set source_profile iam
    aws --profile stitch_prod_admin_global configure set mfa_serial "arn:aws:iam::240342446256:mfa/$user_name"

    # admin_global
    aws --profile admin_global configure set role_arn 'arn:aws:iam::218546966473:role/admin_global'
    aws --profile admin_global configure set source_profile stitch_dev_keys
    aws --profile admin_global configure set mfa_serial "arn:aws:iam::218546966473:mfa/$user_name"

    # poweruser
    aws --profile poweruser configure set role_arn 'arn:aws:iam::218546966473:role/poweruser'
    aws --profile poweruser configure set source_profile stitch_dev_keys
    aws --profile poweruser configure set mfa_serial "arn:aws:iam::218546966473:mfa/$user_name"

    # read_only
    aws --profile read_only configure set role_arn 'arn:aws:iam::218546966473:role/read_only'
    aws --profile read_only configure set source_profile stitch_dev_keys
    aws --profile read_only configure set mfa_serial "arn:aws:iam::218546966473:mfa/$user_name"

}

export_profile_key() {
    local profile_name="$1"

    if ! aws configure get aws_access_key_id --profile "$profile_name" >/dev/null 2>&1 || ! aws configure get aws_secret_access_key --profile "$profile_name" >/dev/null 2>&1
    then
        echo "# Couldn't find key pair for $profile_name" >&2
        return 1
    fi

    export AWS_ACCESS_KEY_ID="$(aws configure get aws_access_key_id --profile "$profile_name")"
    export AWS_SECRET_ACCESS_KEY="$(aws configure get aws_secret_access_key --profile "$profile_name")"

    echo "# AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID"
    echo "# AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY"
}

configure_stitch_dev_keys() {
    local my_user="$1"

    if [[ -z $my_user ]]
    then
        echo "# Usage:" >&2
        echo "# configure_stitch_dev_keys <aws username>" >&2
        return 1
    fi

    if aws configure get aws_access_key_id --profile stitch_dev_keys >/dev/null 2>&1 && aws configure get aws_secret_access_key --profile stitch_dev_keys >/dev/null 2>&1
    then
        tput setaf 2
        tput bold
        echo "# You already have a stitch_dev_keys keypair" >&2
        tput sgr0
        return 0
    fi

    if ! aws iam create-access-key --user-name "$my_user" >~/.stitch/access-key-cache
    then
        tput setaf 1
        tput bold
        echo "# Couldn't create stitch_dev_keys pair for user $my_user"
        tput sgr0
        return 1
    fi

    local access_key="$(jq -r '.AccessKey.AccessKeyId' < ~/.stitch/access-key-cache)"
    local secret_key="$(jq -r '.AccessKey.SecretAccessKey' < ~/.stitch/access-key-cache)"

    aws --profile stitch_dev_keys configure set aws_access_key_id "$access_key"
    aws --profile stitch_dev_keys configure set aws_secret_access_key "$secret_key"

    tput setaf 2
    tput bold
    echo "Successfully configured the stitch_dev_keys profile." >&2
    tput sgr0

    echo "AWS_ACCESS_KEY_ID=$(aws --profile stitch_dev_keys configure get aws_access_key_id)"
    echo "AWS_SECRET_ACCESS_KEY=$(aws --profile stitch_dev_keys configure get aws_secret_access_key)"
}
