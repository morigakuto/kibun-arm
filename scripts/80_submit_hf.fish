#!/usr/bin/env fish
# 提出用に HF へアップロードする（private・チーム名入り）。
#
#   TEAM=team7 ./80_submit_hf.fish
#   TEAM=team7 MODEL=~/lerobot-kibun/outputs/train/smolvla_daruma_v3/checkpoints/last/pretrained_model ./80_submit_hf.fish
#
# 事前にハッカソン用アカウントでログインしておくこと:
#   hf auth login        # write権限のトークンを貼る
#   hf auth whoami       # アカウント名を確認
#
# 作られるもの（両方 private）:
#   <account>/<TEAM>-dataset-daruma    データセット
#   <account>/<TEAM>-smolvla-daruma    学習済みモデル
source (dirname (status filename))/../env.fish

if not set -q TEAM
    echo "TEAM を指定してください: TEAM=team7 ./80_submit_hf.fish"
    exit 1
end

cd $LEROBOT_DIR

# ログイン中のアカウントを取得
set acct (uv run hf auth whoami 2>/dev/null | head -1 | string replace -r '^.*:\s*' '')
if test -z "$acct"
    echo "HFにログインしていません: uv run hf auth login"
    exit 1
end
echo "アカウント: $acct"

# ── データセット ───────────────────────────────────────────────
set base $HOME/.cache/huggingface/lerobot
set ds_root (find $base -maxdepth 2 -type d -name 'daruma_v2_*' ! -name '*_old' 2>/dev/null | sort | tail -1)
if test -z "$ds_root"
    echo "daruma_v2 のデータセットが見つかりません"
    exit 1
end
set ds_repo $acct/{$TEAM}-dataset-daruma
echo ""
echo "== データセット =="
echo "  $ds_root"
echo "  → https://huggingface.co/datasets/$ds_repo （private）"
uv run python -c "
from lerobot.datasets.lerobot_dataset import LeRobotDataset
ds = LeRobotDataset('TECHIdesu/daruma_v2', root='$ds_root')
ds.repo_id = '$ds_repo'
ds.push_to_hub(private=True, tags=['LeRobot','so101','imitation-learning'])
"

# ── モデル ────────────────────────────────────────────────────
set -q MODEL; or set -gx MODEL $HOME/lerobot-kibun/outputs/train/smolvla_daruma_v3/checkpoints/last/pretrained_model
if not test -d $MODEL
    echo ""
    echo "⚠ モデルが見つかりません: $MODEL"
    echo "  存在するチェックポイント:"
    find $HOME/lerobot-kibun/outputs/train -name pretrained_model 2>/dev/null | sed 's/^/    /'
    exit 1
end
set m_repo $acct/{$TEAM}-smolvla-daruma
echo ""
echo "== モデル =="
echo "  $MODEL"
echo "  → https://huggingface.co/$m_repo （private）"
uv run hf upload $m_repo $MODEL . --repo-type=model --private

echo ""
echo "✓ 完了"
echo "  データセット: https://huggingface.co/datasets/$ds_repo"
echo "  モデル:       https://huggingface.co/$m_repo"
