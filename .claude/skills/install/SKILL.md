---
name: install
description: fm をこのマシンにビルドしてインストールする。リリースビルドして fm バイナリを PATH 上に配置したいときに使う。
argument-hint: [PREFIX=<path>]
allowed-tools: Bash
---

# Install fm

`fm` をリリースビルドしてこのマシンにインストールする。

## 手順

1. `make install` を実行する（内部で `swift build -c release` → `install` を行う）。
   - インストール先を変えたい場合は `make install PREFIX=$ARGUMENTS`（デフォルト: `/usr/local`）。
   - [必須] PREFIX に `~` を使わない。Makefile が `"$(PREFIX)/bin"` とクォートするため `~` が展開されず、カレントに `./~/.local/bin/` という偽ディレクトリを作る。チルダ展開したいときは `$HOME` を使う（例: `make install PREFIX=$HOME/.local`）。
2. 成否を確認: `which fm` で実行されるパス、`fm --version`、`fm check` を実行し、インストール先・バージョン・Apple Intelligence の利用可否を報告する。
   - `fm --version` が古い文字列を返したら、PATH 上で別の古い `fm` が優先されている。`which fm` のパスと PREFIX が一致するか確認する。

## メモ

- `/usr/local/bin` は root 所有で sudo が必要。その場合はユーザーに伝えてコマンドを提示する（こちらで sudo は走らせない）。`~/.local/bin` は PATH 上にあり sudo 不要なので、デフォルトの代替として勧めてよい（その際も `PREFIX=$HOME/.local`）。
- ビルドが失敗したらエラーをそのまま報告し、インストールは行わない。
