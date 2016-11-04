#!/usr/bin/env bash

backup() {
    if [[ -d "$1" ]]
    then
        cp -Rv "$1" "${1%%+(/)*}"."$(iso8601)".bak
    else
        cp -v "$1" "$1"."$(iso8601)".bak
    fi
}
