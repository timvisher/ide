.DEFAULT_GOAL := test

readme:
	docker run -v "$$PWD":/mnt -w /mnt mozilla/node-doctoc doctoc --title '**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*' README.md

test: readme
	bash -c '[[ $$(docker run koalaman/shellcheck:v0.4.7 -V) == *0.4.7* ]]'
	git --no-pager diff --exit-code README.md >/dev/null 2>&1
	find . -type f -name '*.bash' -exec docker run -v "$$PWD:/mnt" koalaman/shellcheck:v0.4.7 --shell=bash --format=gcc '{}' \+
