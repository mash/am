PREFIX ?= /usr/local
BIN := .build/release/fm

.PHONY: build install uninstall clean test

build:
	swift build -c release

install: build
	install -d "$(PREFIX)/bin"
	install "$(BIN)" "$(PREFIX)/bin/fm"

uninstall:
	rm -f "$(PREFIX)/bin/fm"

clean:
	swift package clean
	rm -rf .build

test: build
	@echo "hello, answer in one word" | $(BIN) --check
