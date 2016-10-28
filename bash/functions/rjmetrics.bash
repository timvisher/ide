rjmadmin() {
    ssh -t echo connect-masterdb
}

core_forward() {
    ssh -fnL"$1":localhost:"$1" core sleep 30
}

convert_and_open() {
    open $(pbpaste | sed s/https/http/ | sed 's#pipeline.rjmetrics.com/#pipeline.localhost.dev:5000/#')
}
