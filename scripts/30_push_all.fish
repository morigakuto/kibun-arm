#!/usr/bin/env fish
# データセットを HF Hub へ push する。
#   ./30_push_all.fish              → expressive functional 両方
#   ./30_push_all.fish expressive   → expressive だけ（1st pass直後の早期検証で使う）
#
# ローカルのフォルダ名にはタイムスタンプが付いているが、Hub 上は
# TECHIdesu/nuzzle_hand_v1_expressive のような**きれいな名前**で公開する
# （学習スクリプトと提出物の見栄えのため）。
source (dirname (status filename))/../env.fish

set conds $argv
if test (count $conds) -eq 0
    set conds expressive functional
end

cd $LEROBOT_DIR
for cond in $conds
    if not set repo (kibun_repo $cond)
        echo "skip (まだ録画していない): $cond"
        continue
    end
    set root (kibun_root $repo)
    set clean $HF_USER/{$DATASET_PREFIX}_$cond
    echo "== push $root"
    echo "        → https://huggingface.co/datasets/$clean"
    uv run python -c "
from lerobot.datasets.lerobot_dataset import LeRobotDataset
ds = LeRobotDataset('$repo', root='$root')
ds.repo_id = '$clean'          # Hub 側はタイムスタンプなしの名前で公開
ds.push_to_hub()
"
end
echo ""
echo "学習マシンでは、この名前で参照される:"
for cond in $conds
    echo "  $HF_USER/{$DATASET_PREFIX}_$cond"
end
