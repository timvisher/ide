core_forward() {
    ssh -fnL"$1":localhost:"$1" core sleep 30
}
