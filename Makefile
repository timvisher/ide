install:
	npm install

readme:
	./node_modules/.bin/doctoc README.md

test: readme
	git --no-pager diff --exit-code README.md >/dev/null 2>&1
	shellcheck bash/functions/aws.bash
