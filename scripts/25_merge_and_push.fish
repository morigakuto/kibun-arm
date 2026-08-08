#!/usr/bin/env fish
# 2条件のデータセットを1つに統合し（タスク文字列はエピソードごとに保持される）、
# SmolVLA学習用として HF Hub へ push する。
# 実行タイミング: 両条件の録画完了 → 悪エピソード削除後（30_push_all.fish の後でOK）
source (dirname (status filename))/../env.fish

if not set repo_expr (kibun_repo expressive)
    echo "expressive のデータセットがありません"
    exit 1
end
if not set repo_func (kibun_repo functional)
    echo "functional のデータセットがありません"
    exit 1
end
set root_expr (kibun_root $repo_expr)
set root_func (kibun_root $repo_func)
set merged $HF_USER/{$DATASET_PREFIX}_mixed

echo "統合: $repo_expr + $repo_func → $merged"

cd $LEROBOT_DIR
uv run lerobot-edit-dataset \
    --operation.type=merge \
    --operation.repo_ids="[$repo_expr, $repo_func]" \
    --operation.roots="[$root_expr, $root_func]" \
    --new_repo_id="$merged" \
    --push_to_hub=true

echo "統合完了: $merged"
echo "次: train/train_remote.sh を Ubuntu の学習マシンへ持っていって実行"
