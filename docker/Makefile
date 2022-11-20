default:
	@echo "Available targets:"
	@grep -P '^[\w\-]+:' Makefile|grep -v ":="|cut -f1 -d:|grep -v -E '^default'|sed 's/^/    /g'
	@echo

ifndef VERBOSE
.SILENT:
endif

build-image:
	docker build -t z88dk-rage1 .
