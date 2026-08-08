#!/usr/bin/env bash
# 学習済みポリシーを Ubuntu 機の実機で走らせる（アーム・カメラを Ubuntu に繋いだ場合）。
#
#   ./rollout_ubuntu.sh <expressive|functional> [本数=3] [policy_path]
#
# 起動時に:
#   1) キャリブレーションを ~/.cache/... へ配置（無いと事故る。calibration/README.md 参照）
#   2) シリアルポートとカメラを自動検出
#   3) ポートのパーミッションを確認
set -euo pipefail

# uv は curl インストーラで ~/.local/bin に入る。新しいシェルでは PATH に無いことがあるので通す
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
if ! command -v uv >/dev/null 2>&1; then
  echo "✗ uv が見つかりません。インストール:"
  echo "    curl -LsSf https://astral.sh/uv/install.sh | sh"
  echo "  既に入っているなら場所を確認: ls ~/.local/bin/uv ~/.cargo/bin/uv"
  exit 1
fi

HF_USER=TECHIdesu
PREFIX=nuzzle_hand_v1
WORKDIR="${WORKDIR:-$HOME/lerobot-kibun}"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FPS="${FPS:-20}"

COND="${1:-expressive}"
NUM="${2:-3}"

# vcodec: "auto" はハードウェアエンコーダ(h264_nvenc)を優先するが、この機体では
#   avcodec_open2(h264_nvenc) が失敗する（NVML も初期化できていないのでドライバ/ライブラリの不整合）。
# 640x480@20fps ならソフトウェアエンコードで十分速い。
VCODEC="${VCODEC:-h264}"

# SmolVLA は smolvla_base の入力名（camera1/2/3）を引き継ぐので、学習時に
#   --rename_map='{"observation.images.side": "observation.images.camera1"}'
# を付けた。ロボットは observation.images.side を出すため、推論側にも同じ変換が要る。
# ACT は自前のデータセットの特徴名で学習するので不要。
#   RENAME=1 ./rollout_ubuntu.sh expressive 3 <smolvlaのcheckpoint>
RENAME_ARG=""
if [ "${RENAME:-0}" = "1" ]; then
  RENAME_ARG='--rename_map={"observation.images.side": "observation.images.camera1"}'
fi

case "$COND" in
  expressive) TASK="Notice the hand and nuzzle it affectionately" ;;
  functional) TASK="Move to the hand" ;;
  *) echo "usage: $0 <expressive|functional> [本数] [policy_path]"; exit 1 ;;
esac

POLICY="${3:-$WORKDIR/outputs/train/act_${PREFIX}_${COND}/checkpoints/last/pretrained_model}"
if [ ! -d "$POLICY" ]; then
  echo "ポリシーが見つかりません: $POLICY"
  echo "存在するチェックポイント:"
  find "$WORKDIR/outputs/train" -name pretrained_model 2>/dev/null | sed 's/^/  /'
  exit 1
fi

# ── 0) feetech（モーターSDK）が入っているか ──────────────────
# 学習用に作った環境（--extra training --extra smolvla）には入っていない。
# 無いと robot 接続時に ImportError: 'feetech-servo-sdk' is required で落ちる。
if ! (cd "$WORKDIR" && uv run python -c "import scservo_sdk" >/dev/null 2>&1); then
  echo "feetech ドライバが未インストールなので追加します（1〜2分）..."
  (cd "$WORKDIR" && uv sync --locked --python "$PYTHON_VERSION" \
      --extra training --extra smolvla --extra feetech)
fi

# ── 1) キャリブレーションを配置 ────────────────────────────────
CAL_DST_R="$HOME/.cache/huggingface/lerobot/calibration/robots/so_follower"
CAL_DST_T="$HOME/.cache/huggingface/lerobot/calibration/teleoperators/so_leader"
mkdir -p "$CAL_DST_R" "$CAL_DST_T"
cp -n "$REPO_DIR/calibration/follower.json" "$CAL_DST_R/" 2>/dev/null || true
cp -n "$REPO_DIR/calibration/leader.json"   "$CAL_DST_T/" 2>/dev/null || true
echo "キャリブレーション: $CAL_DST_R/follower.json $([ -f "$CAL_DST_R/follower.json" ] && echo OK || echo 見つからない)"

# ── 2) シリアルポート検出 ──────────────────────────────────────
mapfile -t PORTS < <(ls /dev/ttyACM* 2>/dev/null || true)
if [ "${#PORTS[@]}" -eq 0 ]; then
  echo "✗ /dev/ttyACM* が見つかりません。USBを挿し直すか dmesg | tail を確認"
  exit 1
fi
FOLLOWER_PORT="${FOLLOWER_PORT:-${PORTS[0]}}"
echo "フォロワーのポート: $FOLLOWER_PORT   (候補: ${PORTS[*]})"
if [ ! -w "$FOLLOWER_PORT" ]; then
  echo "✗ $FOLLOWER_PORT に書き込めません。次のどちらかを実行:"
  echo "    sudo chmod 666 $FOLLOWER_PORT          # その場しのぎ"
  echo "    sudo usermod -aG dialout \$USER        # 恒久的（再ログインが必要）"
  exit 1
fi

# ── 3) カメラ検出 ──────────────────────────────────────────────
CAM_INDEX="${CAM_INDEX:-0}"
echo "カメラ: index $CAM_INDEX   (候補: $(ls /dev/video* 2>/dev/null | tr '\n' ' '))"
echo "  ※ 映らない/違うカメラなら CAM_INDEX=2 のように指定し直す"
echo "  ※ Linux は1台のカメラに /dev/video0 と /dev/video1 を割り当てることがある（偶数側が本体）"

cd "$WORKDIR"
echo ""
echo "== $COND / $NUM 本 =="
echo "policy: $POLICY"
echo "task:   \"$TASK\""
echo "⚠ キャリブレーションのプロンプトが出たら必ず ENTER（'c' は絶対に押さない）"
echo ""

uv run lerobot-rollout \
    --strategy.type=episodic \
    --policy.path="$POLICY" \
    --policy.device=cuda \
    --robot.type=so101_follower \
    --robot.port="$FOLLOWER_PORT" \
    --robot.id=follower \
    --robot.cameras="{side: {type: opencv, index_or_path: $CAM_INDEX, width: 640, height: 480, fps: 30}}" \
    --robot.max_relative_target=5 \
    --dataset.repo_id="$HF_USER/rollout_${COND}" \
    --dataset.num_episodes="$NUM" \
    --dataset.fps="$FPS" \
    --dataset.push_to_hub=false \
    --dataset.streaming_encoding=true \
    --dataset.rgb_encoder.vcodec="$VCODEC" \
    --task="$TASK" \
    --fps="$FPS" \
    --display_data=false \
    ${RENAME_ARG:+"$RENAME_ARG"}
