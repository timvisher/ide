#!/usr/bin/env bash

cd "$(git rev-parse --show-toplevel)"

go build -o aws-vault .
