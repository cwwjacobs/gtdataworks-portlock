VERSION := $(shell cat VERSION 2>/dev/null || echo 1.0.0)
PREFIX  ?= /usr/local
.PHONY: help install uninstall deb apt-repo check clean

help:
	@echo "GTDataworks Portlock $(VERSION)"
	@echo "  make install    — system install (needs sudo)"
	@echo "  make uninstall  — remove system bits"
	@echo "  make deb        — build a .deb under dist/"
	@echo "  make apt-repo   — build static apt repo (packaging/apt-repo)"
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
	bash -n packaging/build-deb.sh
	bash -n packaging/build-apt-repo.sh
	bash -n packaging/install-apt.sh
	bash -n website/portlock/install-apt.sh
	bash -n tests/run.sh
	python3 -m py_compile app/portlock.py
	python3 tests/test_session.py
	bash tests/run.sh
	@echo "check ok"

deb:
	./packaging/build-deb.sh

apt-repo: deb
	./packaging/build-apt-repo.sh
	cp packaging/install-apt.sh packaging/apt-repo/install-apt.sh
	chmod 755 packaging/apt-repo/install-apt.sh

clean:
	rm -rf dist packaging/deb-root packaging/apt-repo __pycache__ app/__pycache__