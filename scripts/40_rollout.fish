#!/usr/bin/env fish
# 学習済みポリシーをこのMac（mps）で実機実行し、評価用データセットとして録画する。
#   使い方: ./40_rollout.fish <policy_path> <expressive|functional> [本数=3]
#   例:  ./40_rollout.fish TECHIdesu/smolvla_nuzzle_hand_v1_mixed expressive
#        ./40_rollout.fish TECHIdesu/act_nuzzle_hand_v1_expressive expressive
#        ./40_rollout.fish outputs/eval/smolvla_nuzzle_20000 functional 5
#
# GO/NO-GOの3チェック（README参照）:
#   (1) 手を出さずに回す → expressive はゆらぎ続け、functional は止まっているか
#   (2) 手を9点に出す   → どこでも寄ってくるか
#   (3) 条件を切替える  → まっすぐ来る／気づいて寄ってくる の差が出るか
# 動きが鈍く感じたら --robot.max_relative_target=5 を 10 に上げる。
if test (count $argv) -lt 2
    echo "usage: 40_rollout.fish <policy_path> <expressive|functional> [num_episodes]"
    exit 1
end
set policy $argv[1]
set cond $argv[2]
set n 3
if test (count $argv) -ge 3
    set n $argv[3]
end

switch $cond
    case expressive
        set task "Notice the hand and nuzzle it affectionately"
    case functional
        set task "Move to the hand"
    case '*'
        echo "unknown condition: $cond"
        exit 1
end

source (dirname (status filename))/../env.fish
set ts (date +%Y%m%d_%H%M%S)
set eval_repo $HF_USER/rollout_nuzzle_{$cond}_$ts

cd $LEROBOT_DIR
uv run lerobot-rollout \
    --strategy.type=episodic \
    --policy.path="$policy" \
    --policy.device=mps \
    --robot.type=so101_follower \
    --robot.port="$FOLLOWER_PORT" \
    --robot.id="$FOLLOWER_ID" \
    --robot.cameras="$CAMERAS" \
    --robot.max_relative_target=5 \
    --dataset.repo_id="$eval_repo" \
    --dataset.num_episodes=$n \
    --dataset.fps=$FPS \
    --dataset.streaming_encoding=true \
    --dataset.rgb_encoder.vcodec=$VCODEC \
    --task="$task" \
    --fps=$FPS \
    --display_data=false
