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
   - インストール先を変えたい場合は `make install PREFIX=$ARGUMENTS`（デフォルト: `/usr/local`、例: `~/.local`）。
2. 成否を確認: `which fm` と `fm check` を実行し、インストール先と Apple Intelligence の利用可否を報告する。

## メモ

- `/usr/local/bin` への書き込みに sudo が必要なら、その旨をユーザーに伝えてコマンドを提示する（こちらで sudo は走らせない）。
- ビルドが失敗したらエラーをそのまま報告し、インストールは行わない。
