#!/usr/bin/env fish
# daruma データセットのタスク文字列を全エピソードで統一する。
# 録画途中で文章を変えたので、学習の直前に1回だけ実行すること。
#   ./12_unify_task.fish
#
# 学習時と推論時で文字列が完全に一致していないと言語条件付けは効かない。
# rollout 側の文字列は train/rollout_daruma.sh に同じものを入れてある。
source (dirname (status filename))/../env.fish

set task "Steal the cube, but freeze when the red demon is watching"
set base $HOME/.cache/huggingface/lerobot/$HF_USER
set found (find $base -maxdepth 1 -type d -name 'daruma_v1_*' ! -name '*_old' 2>/dev/null | sort)
set valid
for d in $found
    if test -f $d/meta/info.json -a -f $d/meta/tasks.parquet
        set -a valid $d
    end
end
if test (count $valid) -eq 0
    echo "daruma のデータセットが見つかりません"
    exit 1
end

set root $valid[-1]
set repo $HF_USER/(basename $root)
echo "対象: $repo"
echo "統一する文字列: \"$task\""

cd $LEROBOT_DIR
uv run lerobot-edit-dataset \
    --repo_id="$repo" \
    --root="$root" \
    --operation.type=modify_tasks \
    --operation.new_task="$task"

if test $status -ne 0
    echo "✗ 失敗しました。--operation.type=modify_tasks は元を _old に退避するので"
    echo "  $root が消えていたら {$root}_old から戻せます"
    exit 1
end
echo "✓ 統一完了"
