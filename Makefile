.DEFAULT_GOAL := test

install:
	npm install

readme: install
	./node_modules/.bin/doctoc README.md

test: readme
	bash -c '[[ $$(docker run koalaman/shellcheck:v0.4.7 -V) == *0.4.7* ]]'
	git --no-pager diff --exit-code README.md >/dev/null 2>&1
	make -C bash/functions
