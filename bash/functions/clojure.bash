rebl() {
    echo 'ALPHA' >&2
    clojure -Sdeps "{:deps {com.bhauman/rebel-readline {:mvn/version \"0.1.3\"}}}" -m rebel-readline.main
}
