#!/usr/bin/env bash
# 「だるまさんが盗んだ」の実機推論。
#   ./rollout_daruma.sh <act|smolvla> [本数=3]
#
# SmolVLA は smolvla_base の入力名を引き継ぐので rename が要る（自動で付ける）。
# ACT は不要。
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

WORKDIR="${WORKDIR:-$HOME/lerobot-kibun}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FPS="${FPS:-20}"
VCODEC="${VCODEC:-h264}"
# ★ 学習時と完全に同一の文字列であること（12_unify_task.fish で揃えたもの）
TASK="Steal the cube, but freeze when the red demon is watching"

KIND="${1:-act}"
NUM="${2:-3}"

case "$KIND" in
  act)
    POLICY="${3:-$WORKDIR/outputs/train/act_daruma/checkpoints/last/pretrained_model}"
    RENAME_ARG=""
    ;;
  smolvla)
    POLICY="${3:-$WORKDIR/outputs/train/smolvla_daruma_v3/checkpoints/last/pretrained_model}"
    RENAME_ARG='--rename_map={"observation.images.wrist": "observation.images.camera1", "observation.images.front": "observation.images.camera2", "observation.images.side": "observation.images.camera3"}'
    ;;
  *) echo "usage: $0 <act|smolvla> [本数] [policy_path]"; exit 1 ;;
esac

if [ ! -d "$POLICY" ]; then
  echo "ポリシーが見つかりません: $POLICY"
  find "$WORKDIR/outputs/train" -name pretrained_model 2>/dev/null | sed 's/^/  /'
  exit 1
fi

# カクつき対策のつまみ（rollout_ubuntu.sh と同じ）
MAXREL="${MAXREL:-15}"
INTERP="${INTERP:-1}"
ROBOT_FPS=$(( FPS * INTERP ))

# キャリブレーション配置
CAL_R="$HOME/.cache/huggingface/lerobot/calibration/robots/so_follower"
mkdir -p "$CAL_R"
cp -n "$REPO_DIR/calibration/follower.json" "$CAL_R/" 2>/dev/null || true

# ポートは by-id の不変名を優先（ttyACM の番号は挿し直しでずれる）
BY_ID=/dev/serial/by-id/usb-1a86_USB_Single_Serial_5B3D042059-if00
if [ -e "$BY_ID" ]; then FOLLOWER_PORT="${FOLLOWER_PORT:-$BY_ID}"; else FOLLOWER_PORT="${FOLLOWER_PORT:-/dev/ttyACM0}"; fi
if [ ! -w "$FOLLOWER_PORT" ]; then
  echo "✗ $FOLLOWER_PORT に書き込めません: sudo chmod 666 \$(readlink -f $FOLLOWER_PORT)"
  exit 1
fi

# カメラは学習時と同一構成でなければならない（3カメラ・by-idの不変パス・MJPG）。
# 1台でも欠けたり名前が違うと特徴量不一致でポリシーが読めない。
BY=/dev/v4l/by-id
CAM_W=$BY/usb-Innomaker_Innomaker-U20CAM-1080p-S1_SN0001-video-index0
CAM_F=$BY/usb-046d_HD_Pro_Webcam_C920-video-index0
CAM_S=$BY/usb-Global_Shutter_Camera_Global_Shutter_Camera_01.00.00-video-index0
CAMERAS="{wrist: {type: opencv, index_or_path: $CAM_W, width: 640, height: 480, fps: 30, fourcc: MJPG}, front: {type: opencv, index_or_path: $CAM_F, width: 640, height: 480, fps: 30, fourcc: MJPG}, side: {type: opencv, index_or_path: $CAM_S, width: 640, height: 480, fps: 30, fourcc: MJPG}}"
cd "$WORKDIR"
echo "== daruma / $KIND / $NUM 本 =="
echo "policy: $POLICY"
echo "task:   \"$TASK\""
echo "⚠ キャリブレーションのプロンプトが出たら必ず ENTER（'c' は押さない）"

uv run lerobot-rollout \
    --strategy.type=episodic \
    --policy.path="$POLICY" \
    --policy.device=cuda \
    --robot.type=so101_follower \
    --robot.port="$FOLLOWER_PORT" \
    --robot.id=follower \
    --robot.cameras="$CAMERAS" \
    --robot.max_relative_target=$MAXREL \
    --dataset.repo_id="TECHIdesu/rollout_daruma_${KIND}" \
    --dataset.num_episodes="$NUM" \
    --dataset.fps="$FPS" \
    --dataset.push_to_hub=false \
    --dataset.streaming_encoding=true \
    --dataset.rgb_encoder.vcodec="$VCODEC" \
    --task="$TASK" \
    --fps="$ROBOT_FPS" \
    --interpolation_multiplier="$INTERP" \
    --display_data=false \
    ${RENAME_ARG:+"$RENAME_ARG"}
