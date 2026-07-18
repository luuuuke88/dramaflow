#!/bin/bash
set -euo pipefail
LIVE="$HOME/Library/Application Support/toonflow"
WORK="$HOME/Documents/dramaflow-w0-blackbox"
BACKUP="$WORK/backup"
ASIDE="$WORK/live-aside"
MANIFEST="$WORK/backup.sha256"

die() { echo "FATAL: $1" >&2; exit 1; }
assert_quit() { pgrep -x ToonFlow >/dev/null && die "ToonFlow 正在运行，先退出"; return 0; }

case "${1:-}" in
  backup)
    assert_quit
    [ -d "$LIVE" ] || die "$LIVE 不存在"
    mkdir -p "$WORK"
    rsync -a --delete "$LIVE/" "$BACKUP/"
    (cd "$BACKUP" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256) > "$MANIFEST"
    sqlite3 "$BACKUP/data/db2.sqlite" "SELECT count(*) FROM o_project;" > "$WORK/project-count.txt"
    echo "backup ok: $(wc -l < "$MANIFEST") files, projects=$(cat "$WORK/project-count.txt")"
    ;;
  verify)
    (cd "$BACKUP" && shasum -a 256 -c "$MANIFEST" --quiet) && echo "backup manifest OK"
    ;;
  isolate)
    assert_quit
    [ -f "$MANIFEST" ] || die "先 backup"
    [ -e "$ASIDE" ] && die "已处于隔离态"
    mv "$LIVE" "$ASIDE"
    echo "isolated: 打包版下次启动将创建全新数据目录"
    ;;
  restore)
    assert_quit
    [ -d "$ASIDE" ] || die "不在隔离态"
    [ -e "$LIVE" ] && rm -rf "$LIVE"   # 会话产生的临时数据，整体丢弃
    mv "$ASIDE" "$LIVE"
    (cd "$LIVE" && shasum -a 256 -c "$MANIFEST" --quiet) || die "恢复后哈希不一致，用 $BACKUP 排查"
    LIVE_COUNT=$(sqlite3 "$LIVE/data/db2.sqlite" "SELECT count(*) FROM o_project;")
    [ "$LIVE_COUNT" = "$(cat "$WORK/project-count.txt")" ] || die "项目数不一致"
    echo "restore ok: projects=$LIVE_COUNT"
    ;;
  *) die "usage: blackbox_toonflow.sh backup|verify|isolate|restore" ;;
esac
