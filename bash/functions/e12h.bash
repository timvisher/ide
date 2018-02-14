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

e12h_cat_allocation() {
    _e12h_get '_cat/allocation?v&s=disk.percent' | column -t
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
