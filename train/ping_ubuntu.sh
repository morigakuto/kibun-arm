#!/usr/bin/env bash
# 各 /dev/ttyACM* でモーター1〜6が応答するか確認する（読み出しのみ。アームは動かない）。
#   - どちらのポートがフォロワーか分からない時
#   - ConnectionError（no status packet / Incorrect status packet）が出た時
set -uo pipefail
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
WORKDIR="${WORKDIR:-$HOME/lerobot-kibun}"

cd "$WORKDIR"
for port in /dev/ttyACM*; do
  [ -e "$port" ] || continue
  echo "=== $port ==="
  uv run python - "$port" <<'PY' 2>&1 | grep -v "^INFO\|^WARNING"
import sys
from lerobot.motors.feetech import FeetechMotorsBus
from lerobot.motors import Motor, MotorNormMode

port = sys.argv[1]
motors = {f"m{i}": Motor(i, "sts3215", MotorNormMode.RANGE_M100_100) for i in range(1, 7)}
bus = FeetechMotorsBus(port=port, motors=motors)
names = {1: "shoulder_pan", 2: "shoulder_lift", 3: "elbow_flex",
         4: "wrist_flex", 5: "wrist_roll", 6: "gripper"}
try:
    bus.connect(handshake=False)
except Exception as e:
    print(f"  接続失敗: {type(e).__name__}: {e}")
    raise SystemExit

ok, ng = [], []
for i in range(1, 7):
    try:
        bus.ping(i)
        ok.append(i)
    except Exception:
        ng.append(i)

for i in range(1, 7):
    mark = "OK " if i in ok else "✗  "
    print(f"  id={i} {names[i]:<14} {mark}")

if not ng:
    print("  → 全6モーター応答。バスは健全")
else:
    first = min(ng)
    print(f"  → id={first} 以降が応答しない。デイジーチェーンで id={first} の"
          f"手前のケーブル、または id={first} 自体の過負荷/発熱を疑う")
    print("     対処: アームの電源を10秒抜いて挿し直す（ラッチしたエラー状態がリセットされる）")
try:
    bus.disconnect()
except Exception:
    pass
PY
done
echo ""
echo "フォロワーが /dev/ttyACM1 だった場合の実行:"
echo "  FOLLOWER_PORT=/dev/ttyACM1 ./rollout_ubuntu.sh expressive 3"
