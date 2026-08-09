#!/usr/bin/env fish
# 「だるまさんが盗んだ」用の録画。
#   ./11_record_daruma.fish [本数=40]
#
# キー操作は 10_record.fish と同じ:
#   →(n) フェーズ終了（1本につき2回: 演技終了 → リセット終了）
#   ←(r) 撮り直し / Esc(q) 終了
#   ⚠ 連打禁止。1回押したら音声アナウンスを待つ（1フレームepisodeでデータセットが壊れる）
#
# ══════════════════════════════════════════════════════════════
#  1エピソードの流れ
# ══════════════════════════════════════════════════════════════
#   黒面 → キューブへ接近 → 掴む → 巣へ運ぶ → 置く
#   ただし途中でランダムに赤鬼が出る → その場で静止 → 黒面に戻ったら再開
#
#   赤鬼を出すフェーズを毎回変える（偏らせない）:
#     接近中 / グリッパーを下ろす途中 / 掴む直前 / 掴んだ直後 / 運搬中 / 置く直前
#
#   ★ 停止フレームが多すぎると「常に止まるモデル」になる。
#     赤鬼は1回の停止あたり1〜2秒まで。1エピソードで2〜3回まで。
#
#   ★ 反実仮想ペア: 同じ姿勢で黒面なら続行、赤鬼なら保持。
#     同じ場所で両方を録ると「作業フェーズ」ではなく「カードを見て」判断するようになる。
#
# ══════════════════════════════════════════════════════════════
#  撮影条件
# ══════════════════════════════════════════════════════════════
#   - カードを操作する人の手は衝立の裏に隠す（画面で変わるのはカードだけにする）
#   - カメラの自動露出/ホワイトバランスは固定（黒面で画面全体が暗くなるのを手掛かりにさせない）
#   - グリッパーは今回**使う**（把持する）。リーダーのトリガーの輪ゴムは外すこと
source (dirname (status filename))/../env.fish

set n 40
if test (count $argv) -ge 1
    set n $argv[1]
end

set prefix daruma_v1
set task "Steal the cube when not being watched"

set -q EP_TIME; or set -gx EP_TIME 600
set -q RESET_TIME; or set -gx RESET_TIME 600
set -q DISPLAY_DATA; or set -gx DISPLAY_DATA false

# 既存があれば追記、無ければ新規（10_record.fish と同じ解決方法。壊れたものは弾く）
set base $HOME/.cache/huggingface/lerobot/$HF_USER
set found (find $base -maxdepth 1 -type d -name "$prefix"_'*' ! -name '*_old' 2>/dev/null | sort)
set valid
for d in $found
    if test -f $d/meta/info.json -a -f $d/meta/tasks.parquet
        set -a valid $d
    end
end

set extra_flags
if test (count $valid) -gt 0
    set repo $HF_USER/(basename $valid[-1])
    set root $HOME/.cache/huggingface/lerobot/$repo
    set extra_flags --resume=true --dataset.root="$root"
    set have (python3 -c "import json;print(json.load(open('$root/meta/info.json'))['total_episodes'])" 2>/dev/null; or echo '?')
    echo "既存データセットに追記します: $repo （現在 $have 本）"
else
    set repo $HF_USER/$prefix
    echo "新規作成します（実際の名前にはタイムスタンプが付きます）"
end

echo "== daruma / $n 本 =="
echo "task: \"$task\""
echo "→(n)=フェーズ終了（1本につき2回） ←(r)=撮り直し Esc(q)=終了"
echo "⚠ 連打禁止。1回押したら音声アナウンスを待つこと"
echo "⚠ 'Record loop is running slower' が出たら止めて相談"

cd $LEROBOT_DIR
uv run lerobot-record \
    --robot.type=so101_follower \
    --robot.port="$FOLLOWER_PORT" \
    --robot.id="$FOLLOWER_ID" \
    --teleop.type=so101_leader \
    --teleop.port="$LEADER_PORT" \
    --teleop.id="$LEADER_ID" \
    --robot.cameras="$CAMERAS" \
    --dataset.repo_id="$repo" \
    --dataset.single_task="$task" \
    --dataset.num_episodes=$n \
    --dataset.episode_time_s=$EP_TIME \
    --dataset.reset_time_s=$RESET_TIME \
    --dataset.fps=$FPS \
    --dataset.push_to_hub=false \
    --dataset.streaming_encoding=true \
    --dataset.encoder_threads=2 \
    --dataset.rgb_encoder.vcodec=$VCODEC \
    --play_sounds=true \
    --display_data=$DISPLAY_DATA \
    $extra_flags
