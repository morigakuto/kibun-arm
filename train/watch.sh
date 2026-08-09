#!/usr/bin/env bash
# 学習の状態を監視し続ける。Ctrl-C で終了（学習は止まらない）。
#   ./watch.sh                      # 既定 ~/smolvla_v3.log を15秒ごと
#   ./watch.sh ~/act_v2.log 5       # ログと間隔を指定
LOG="${1:-$HOME/smolvla_v3.log}"
INTERVAL="${2:-15}"
OUTDIR="${OUTDIR:-$HOME/lerobot-kibun/outputs/train}"

while true; do
  clear
  echo "==================== $(date '+%H:%M:%S') ===================="
  echo "log: $LOG"
  echo ""

  echo "── 進捗 ────────────────────────────────"
  tr '\r' '\n' < "$LOG" 2>/dev/null \
    | grep -oE '[0-9]+/[0-9]+ \[[0-9:]+<[0-9:]+, *[0-9.]+step/s\]' | tail -1 \
    | sed 's/^/  /' || echo "  (まだ出力なし)"

  echo ""
  echo "── loss（新しい順に3件）─────────────────"
  tr '\r' '\n' < "$LOG" 2>/dev/null \
    | grep -oE 'step:[0-9KM]+ .*loss:[0-9.]+ grdn:[0-9.]+ lr:[0-9.e-]+' | tail -3 \
    | sed 's/^/  /'

  echo ""
  echo "── 保存済みチェックポイント ──────────────"
  for d in "$OUTDIR"/*/checkpoints; do
    [ -d "$d" ] || continue
    job=$(basename "$(dirname "$d")")
    ck=$(ls "$d" 2>/dev/null | grep -v last | tr '\n' ' ')
    [ -n "$ck" ] && echo "  $job: $ck"
  done

  echo ""
  echo "── ディスク / プロセス ───────────────────"
  echo "  空き: $(df -h / | tail -1 | awk '{print $4}')"
  echo "  学習プロセス: $(ps -eo cmd | grep -c '^uv run lerobot-train')"

  # エラーが出ていたら目立たせる
  ERR=$(tr '\r' '\n' < "$LOG" 2>/dev/null | grep -iE 'error|Traceback|No space left' | tail -2)
  if [ -n "$ERR" ]; then
    echo ""
    echo "── ⚠ エラー ─────────────────────────────"
    echo "$ERR" | sed 's/^/  /'
  fi

  echo ""
  echo "(Ctrl-C で監視終了。学習は止まりません)"
  sleep "$INTERVAL"
done
