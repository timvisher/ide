.DEFAULT_GOAL := test

test:
	docker run -v "$$PWD:/mnt" koalaman/shellcheck:v0.4.7 --shell=bash --format=gcc -- *
