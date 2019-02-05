.DEFAULT_GOAL := test

readme:
	docker run -v "$$PWD":/mnt mozilla/node-doctoc bash -c 'cd /mnt && doctoc --title "**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*" README.md'

test: readme
	bash -c '[[ $$(docker run koalaman/shellcheck:v0.4.7 -V) == *0.4.7* ]]'
	git --no-pager diff --exit-code README.md >/dev/null 2>&1
	make -C bash/functions
