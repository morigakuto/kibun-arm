#!/usr/bin/env bash
# きぶんのあるアーム — 学習一式（Ubuntu + NVIDIA GPU 用、bash）
#
# ★ 会社PCなどで「どこにもログインしたくない」場合、この構成でログインは一切不要:
#     - GitHub: 公開リポジトリの clone は**匿名**。アカウント不要
#     - PyPI  : uv sync は匿名
#     - HF    : データセットもモデル(smolvla_base)も公開なのでダウンロードは匿名。
#               学習結果は PUSH_TO_HUB=false（既定）でローカルに置き、USB で Mac へ戻す。
#               Mac 側は既にログイン済みなので、提出用の push はそちらでやる
#
# 使い方:
#   ./train_remote.sh act                      # 条件別ACT×2（各30〜60分）
#   ./train_remote.sh smolvla                  # 本命 SmolVLA（3〜6時間）
#   ./train_remote.sh all                      # 全部
#   STEPS=8000 ./train_remote.sh act expressive   # ★スモークテスト（約15分）
#
# 環境変数:
#   PUSH_TO_HUB=true   … HF へ直接 push する（要 hf auth login）。既定 false
#   DATA_ROOT=/path    … USBで持ち込んだデータセットを使う（HFからDLしない）
#                        例: DATA_ROOT=/media/usb/kibun/datasets ./train_remote.sh act
#   WANDB_ENABLE=true  … 既定 false（ログイン不要にするため）
#   STEPS=8000         … 既定 20000
set -euo pipefail

HF_USER=TECHIdesu
PREFIX=nuzzle_hand_v1
LEROBOT_COMMIT=0d383d09        # Mac の録画環境と同一コミット（v0.6.0+40）
WORKDIR="${WORKDIR:-$HOME/lerobot-kibun}"
WANDB_ENABLE="${WANDB_ENABLE:-false}"
PUSH_TO_HUB="${PUSH_TO_HUB:-false}"
DATA_ROOT="${DATA_ROOT:-}"
STEPS="${STEPS:-20000}"

# ★ Python は 3.12 に固定すること。
# lerobot の pyproject は requires-python = ">=3.12" なので、uv は環境にある最新
# （3.14 など）を選んでしまう。Python 3.14 で argparse の add_argument が
# 型を検証するようになり、draccus が `str | None` という Union 型を type= に渡すため
#   TypeError: <class 'str' | None> is not callable
# で引数パース前に落ちる。Mac 側の録画環境も 3.12.12 なので揃えておく。
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"

# ── 環境構築（初回のみ。GitHubログイン不要）──────────────────
if [ ! -d "$WORKDIR" ]; then
  git clone https://github.com/huggingface/lerobot "$WORKDIR"
fi
cd "$WORKDIR"
git fetch --all --quiet || true
git checkout "$LEROBOT_COMMIT"
command -v uv >/dev/null 2>&1 || { curl -LsSf https://astral.sh/uv/install.sh | sh; export PATH="$HOME/.local/bin:$PATH"; }

# 既存の .venv が別バージョンで作られていたら作り直す（3.14で作られた環境が残っていると直らない）
if [ -d .venv ] && ! .venv/bin/python -V 2>/dev/null | grep -q "Python $PYTHON_VERSION"; then
  echo "既存の .venv が Python $PYTHON_VERSION ではないので作り直します: $(.venv/bin/python -V 2>&1)"
  rm -rf .venv
fi
uv sync --locked --python "$PYTHON_VERSION" --extra training --extra smolvla
uv run python -c "import sys, torch; print('Python:', sys.version.split()[0]); assert torch.cuda.is_available(), 'CUDA not available!'; print('GPU:', torch.cuda.get_device_name(0))"

# データセットの指定: DATA_ROOT があればローカル（USB）、無ければ HF から
dataset_args () {
  local name=$1
  if [ -n "$DATA_ROOT" ]; then
    echo "--dataset.repo_id=$HF_USER/$name --dataset.root=$DATA_ROOT/$name"
  else
    echo "--dataset.repo_id=$HF_USER/$name"
  fi
}

# 出力先: push するなら repo_id、しないならローカルのみ
output_args () {
  local name=$1
  if [ "$PUSH_TO_HUB" = "true" ]; then
    echo "--policy.repo_id=$HF_USER/$name"
  else
    echo "--policy.push_to_hub=false"
  fi
}

train_act () {
  local cond=$1
  # chunk_size=50 (20fpsで2.5秒), n_action_steps=20 (1秒ごとに再計画 → 手の移動に追従できる)
  # temporal ensembling はデフォルトOFFのまま（ONにすると はずみ・びくっ が平均でなまる）
  uv run lerobot-train \
    $(dataset_args "${PREFIX}_${cond}") \
    --policy.type=act \
    --policy.device=cuda \
    --policy.chunk_size=50 \
    --policy.n_action_steps=20 \
    --batch_size=32 \
    --steps="$STEPS" \
    --save_freq=5000 \
    --num_workers=8 \
    --output_dir="outputs/train/act_${PREFIX}_${cond}" \
    --job_name="act_${PREFIX}_${cond}" \
    $(output_args "act_${PREFIX}_${cond}") \
    --wandb.enable="$WANDB_ENABLE"
}

train_smolvla () {
  # smolvla_base からのfine-tune。vision encoder を解凍（AGENT_GUIDE §7.6: 特化タスクで大きく効く）
  # OOMになったら --batch_size=16 に落とす（それでも一晩で終わる）
  uv run lerobot-train \
    $(dataset_args "${PREFIX}_mixed") \
    --policy.path=lerobot/smolvla_base \
    --policy.device=cuda \
    --policy.n_action_steps=20 \
    --policy.freeze_vision_encoder=false \
    --policy.train_expert_only=false \
    --policy.scheduler_decay_steps="$STEPS" \
    --batch_size=32 \
    --steps="$STEPS" \
    --save_freq=5000 \
    --num_workers=8 \
    --output_dir="outputs/train/smolvla_${PREFIX}_mixed" \
    --job_name="smolvla_${PREFIX}_mixed" \
    $(output_args "smolvla_${PREFIX}_mixed") \
    --wandb.enable="$WANDB_ENABLE"
}

CONDS="${2:-expressive functional}"   # 第2引数で条件を絞れる: ./train_remote.sh act expressive

case "${1:-all}" in
  act)     for m in $CONDS; do train_act "$m"; done ;;
  smolvla) train_smolvla ;;
  all)     for m in $CONDS; do train_act "$m"; done; train_smolvla ;;
  *) echo "usage: $0 [act|smolvla|all] [expressive|functional]"; exit 1 ;;
esac

echo ""
echo "==================================================================="
echo "完了。チェックポイント:"
find "$WORKDIR/outputs/train" -name pretrained_model -maxdepth 4 2>/dev/null | sed 's/^/  /'
if [ "$PUSH_TO_HUB" != "true" ]; then
  echo ""
  echo "PUSH_TO_HUB=false なので Hub には上げていない。USB で Mac へ戻すには:"
  echo "  cp -r $WORKDIR/outputs/train /media/<USB>/kibun-models/"
  echo "Mac 側: ./scripts/40_rollout.fish <コピー先のpretrained_modelのパス> expressive"
fi
echo "==================================================================="
