##########################################################################
### e12h ide functions
##########################################################################

e12h_url='https://elasticsearch-forwarder.stitchdata.com'

_e12h_get() {
    curl -s "$e12h_url/$1"
}

e12h_recoveries() {
    _e12h_get 'logstash-*/_recovery?human&active_only=true' | jq '.'
}

e12h_cat_recoveries() {
    # TODO add arguments for setting active_only, etc. rather than always
    # setting them?

    _e12h_get '_cat/recovery?v&active_only=true&h=index,shard,time,type,stage,source_node,target_node,bytes_total,bytes_percent&s=index' | column -t
}

_e12h_cat_allocation_show_help() {
    cat <<EOF
usage: e12h_cat_allocation [(-s |--sort=)(disk.percent|node)]
    [(-o |--sort-order=)(asc|desc)]
EOF
}

_e12h_cat_allocation_is_valid_sort_option() {
    if [[ $1 == -* ]]
    then
        _e12h_cat_allocation_show_help
        return 1
    elif [[ $1 != +(disk.allocation|node) ]]
    then
        _e12h_cat_allocation_show_help
        return 1
    fi
}

_e12h_cat_allocation_is_valid_sort_order_option() {
    if [[ $1 == -* ]]
    then
        _e12h_cat_allocation_show_help
        return 1
    elif [[ $1 != +(asc|desc) ]]
    then
        _e12h_cat_allocation_show_help
        return 1
    fi
}

e12h_cat_allocation() {
    local sort=disk.percent
    local sort_order=asc
    while :
    do
        case $1 in
            -h|--help)
                _e12h_cat_allocation_show_help
                return
                ;;
            -s)
                if ! _e12h_cat_allocation_is_valid_sort_option "$2"
                then
                    return 1
                else
                    sort=$2
                    shift
                fi
                ;;
            --sort=?*)
                sort=${1#*=}
                if ! _e12h_cat_allocation_is_valid_sort_option "$sort"
                then
                    return 1
                fi
                ;;
            -o)
                if ! _e12h_cat_allocation_is_valid_sort_order_option "$2"
                then
                    return 1
                else
                    sort_order=$2
                    shift
                fi
                ;;
            --sort-order=?*)
                sort_order=${1#*=}
                if ! _e12h_cat_allocation_is_valid_sort_order_option "$sort"
                then
                    return 1
                fi
                ;;
            -?*)
                printf 'WARN: Unknown option (ignore): %s\n' "$1" >&2
                ;;
            *)
                break
        esac

        shift
    done

    _e12h_get "_cat/allocation?v&h=shards,disk.indices,disk.used,disk.avail,disk.total,disk.percent,node&s=${sort}:${sort_order}" | column -t
}

e12h_cat_snapshots() {
    _e12h_get '_cat/snapshots/logstash-backups?v' | column -t
}

e12h_cat_indices() {
    _e12h_get '_cat/indices?v&s=docs.count' | column -t
}

e12h_cat_shards() {
    _e12h_get '_cat/shards?v&s=store' | column -t
}

_ide_ssh_define_common_service_functions monitoring elasticsearch_forwarder
