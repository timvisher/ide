.DEFAULT_GOAL := test

install:
	npm install

readme: install
	./node_modules/.bin/doctoc README.md

test: readme
	git --no-pager diff --exit-code README.md >/dev/null 2>&1
	make -C bash/functions
