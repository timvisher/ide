_ide_environments_cat_show_help() {
    cat <<EOF
ide_environments_cat vm|sandbox|prod <environment_name> [bash|json]
EOF
}

_ide_environments_assert_preconditions() {
    if ! shopt -q extglob
    then
        echo 'Requires extglob' >&2
        return 1
    fi

    if [[ $environment != @(vm|sandbox|prod) ]]
    then
        _ide_environments_cat_show_help
        return 1
    fi
}

_ide_environments_exists() {
    local environment=$1
    local service=$2

    _ide_environments_assert_preconditions "$environment" || return 1

    ide_environments_ls "$environment" | grep -q ".*${service}.*"
}

ide_environments_cat() {
    local environment=$1
    local service=$2
    local format=${3:-bash}

    _ide_environments_assert_preconditions "$environment" || return 1
    if ! _ide_environments_exists "$environment" "$service"
    then
        echo "# ERROR: $service does not exist in $environment" >&2
        echo "ide_environments_ls $environment" >&2
        return 1
    fi

    if [[ $format != +(bash|json) ]]
    then
        ide_environments_cat_show_help
        return 1
    fi

    bucket=$(_ide_environments_get_environment_bucket "$environment")
    case $format in
         json)
             environment="${environment}.json"
             ;;
    esac

    aws s3 cp \
        s3://"$bucket"/environments/"$service"/"$environment" \
        -
}

_ide_environments_get_environment_bucket() {
    local environment=$1

    _ide_environments_assert_preconditions "$environment" || return 1

    if [[ $environment == +(vm|sandbox) ]]
    then
        echo com-stitchdata-dev-deployment-assets
    else
        echo com-stitchdata-prod-deployment-assets
    fi
}

ide_environments_ls() {
    local environment=$1

    _ide_environments_assert_preconditions "$environment" || return 1

    # shellcheck disable=SC2155
    local bucket=$(_ide_environments_get_environment_bucket "$environment")

    aws s3api \
        list-objects-v2 \
        --bucket "$bucket" \
        --prefix environments \
        | jq -r '[.Contents[] | .Key | split("/") | .[1]] | unique | sort[]'
}
