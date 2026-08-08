#!/usr/bin/env fish
# 2条件のデータセットを1つに統合する（タスク文字列はエピソードごとに保持される）。
# SmolVLA は言語条件付けで2条件を切り替えるので、統合データセットが必須。
# （lerobot-train は複数データセットの同時指定に未対応:
#   "LeRobotMultiDataset is not currently implemented"）
#
#   ./25_merge_and_push.fish          → ローカルに統合のみ（HFログイン不要）
#   PUSH=true ./25_merge_and_push.fish → 統合してHFへpushも
source (dirname (status filename))/../env.fish

if not set repo_expr (kibun_repo expressive)
    echo "expressive のデータセットがありません"
    exit 1
end
if not set repo_func (kibun_repo functional)
    echo "functional のデータセットがありません。先に ./10_record.fish functional 15"
    exit 1
end
set root_expr (kibun_root $repo_expr)
set root_func (kibun_root $repo_func)
set merged $HF_USER/{$DATASET_PREFIX}_mixed
set merged_root (kibun_root $merged)

set -q PUSH; or set -gx PUSH false

echo "統合: $repo_expr + $repo_func"
echo "   → $merged"
echo "   root: $merged_root"

if test -d $merged_root
    echo "⚠ 統合先が既に存在します（前回の失敗の残骸かも）。消してから再実行してください:"
    echo "    rm -rf $merged_root"
    exit 1
end

cd $LEROBOT_DIR
# concatenate_videos=false が重要。true（既定）だと全動画を1本に再多重化しようとして
#   av.error.ValueError: Invalid argument / non monotonically increasing dts
# で落ちる。false なら元の動画ファイルをそのまま参照するので安全かつ一瞬で終わる。
uv run lerobot-edit-dataset \
    --operation.type=merge \
    --operation.repo_ids="[$repo_expr, $repo_func]" \
    --operation.roots="[$root_expr, $root_func]" \
    --operation.concatenate_videos=false \
    --new_repo_id="$merged" \
    --new_root="$merged_root" \
    --push_to_hub=$PUSH

if test $status -ne 0
    echo ""
    echo "✗ 統合に失敗しました。残骸を消してから相談してください:"
    echo "    rm -rf $merged_root"
    exit 1
end

# 中身が読めるか確認してから完了を宣言する
set n (python3 -c "import json;print(json.load(open('$merged_root/meta/info.json'))['total_episodes'])" 2>/dev/null; or echo "")
if test -z "$n"
    echo "✗ 統合先の meta/info.json が読めません。失敗しています"
    exit 1
end

echo ""
echo "✓ 統合完了: $n 本。SmolVLA の学習:"
echo "  cd \$LEROBOT_DIR"
echo "  uv run lerobot-train \\"
echo "    --dataset.repo_id=$merged --dataset.root=$merged_root \\"
echo "    --policy.path=lerobot/smolvla_base --policy.device=cuda \\"
echo "    --policy.n_action_steps=20 --policy.freeze_vision_encoder=false \\"
echo "    --policy.train_expert_only=false --policy.scheduler_decay_steps=20000 \\"
echo "    --batch_size=32 --steps=20000 --save_freq=10000 --num_workers=4 \\"
echo "    --output_dir=outputs/train/smolvla_mixed --job_name=smolvla_mixed \\"
echo "    --policy.push_to_hub=false --wandb.enable=false"
