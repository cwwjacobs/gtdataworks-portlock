VERSION := $(shell cat VERSION 2>/dev/null || echo 0.2.0)
PREFIX  ?= /usr/local
.PHONY: help install uninstall deb check clean

help:
	@echo "GTDataworks Portlock $(VERSION)"
	@echo "  make install    — system install (needs sudo)"
	@echo "  make uninstall  — remove system bits"
	@echo "  make deb        — build a .deb under dist/"
	@echo "  make check      — syntax-check scripts"
	@echo "  make clean      — remove build artifacts"

install:
	./install.sh

uninstall:
	./uninstall.sh

check:
	bash -n sbin/portlock-ctl
	bash -n sbin/portlock-ctl-auto
	bash -n sbin/portlock-attempt-logger
	bash -n install.sh
	bash -n uninstall.sh
	python3 -m py_compile app/portlock.py
	@echo "check ok"

deb:
	./packaging/build-deb.sh

clean:
	rm -rf dist packaging/deb-root __pycache__ app/__pycache__
