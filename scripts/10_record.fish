#!/usr/bin/env fish
# 条件別の録画セッション。
#   使い方: ./10_record.fish <expressive|functional> [本数]
#   同じ条件を再実行すると自動で --resume=true になり追記される。
#
# ══════════════════════════════════════════════════════════════
#  キー操作 — 時間制限ではなく**自分で区切る**
# ══════════════════════════════════════════════════════════════
#   →  (または n) : 今のフェーズを終える。1エピソードにつき2回押す:
#                     1回目 = 演技を終えて録画を止める
#                     2回目 = リセット（アームをホームへ／手をフレーム外へ）を終えて次へ
#   ←  (または r) : 今のエピソードを破棄して撮り直し
#   Esc(または q) : 録画終了・保存して抜ける（即座に効く）
#
#   ⚠⚠ 連打しないこと。1回押したら**音声アナウンスを聞いてから**次を押す。
#      exit_early は単なるフラグなので、フェーズの切れ目に余分な押下が残ると
#      次のフェーズが即座に終了し、**1フレームだけのエピソード**ができる。
#      それが保存時に pyarrow のクラッシュ（stats の列長不一致）を起こし、
#      **セッション全体のメタデータが書けずデータセットが壊れる**。実際に一度やらかした。
#
#   ※ 音声が「Recording episode N」→ 演技フェーズ、「Reset the environment」→ リセットフェーズ。
#      リセット中は録画されていないので、ゆっくり構え直してよい。
#   ※ macOS で矢印キーが効かない場合はアクセシビリティ権限の問題。**n / r / q** を使う（同じ動作）。
#
#   タイムアウトは保険としてのみ設定してある（既定10分）。変えたい時:
#      EP_TIME=180 RESET_TIME=60 ./10_record.fish expressive 20
#
# ══════════════════════════════════════════════════════════════
#  expressive（表現あり / ELEGNT の γ>0 条件）
# ══════════════════════════════════════════════════════════════
#   ★★ 1エピソードに「手を出す→スリスリ→手を引く→戻る」を **2〜3往復** 入れること ★★
#      2026-08-08 の失敗: 往復を録らずエピソードを切っていたため、推論時に
#      「手を引っ込めても戻ってこない」状態になった。リセットフェーズは録画されないので、
#      戻る動作は**エピソードの中に**入れないと一度も学習されない。
#
#   1. 手なしで「探している」ゆらぎ（1〜2秒）
#   2. 手がフレームイン
#   3. 頭だけ手の方へ向ける（0.3〜0.5秒）→ ほんの少しためる  ★溜め
#   4. 一度あなたの顔を見上げる                              ★親しみの最大要因
#   5. わずかに弧を描いて寄る
#   6. 押し込まず沿わせてスリスリ（wrist_roll で2〜3ストローク）
#   7. もう一度顔を見上げる（「これでいい？」）
#   8. ★ 手をフレーム外へ引く → アームは名残惜しそうにホームへ戻る → 探すゆらぎに戻る
#   9. ★ 2〜3 に戻ってもう1〜2往復（手の位置は毎回変える）
#  10. 最後の「戻る」まで終えたら → （尻に静止フレームを残さない）
#   ※ 半分のエピソードでは 6 の途中で手をゆっくり動かし、追従する
#
# ══════════════════════════════════════════════════════════════
#  functional（機能のみ / ELEGNT の γ=0 条件）— 8〜12秒。演技しない
# ══════════════════════════════════════════════════════════════
#   1. ホームポーズで**完全静止**（1〜2秒）。ゆらぎなし
#      （論文で "kinda creepy, as if it was intently staring" と評された状態。狙い通り）
#   2. 手がフレームイン
#   3. 溜めなし・視線なし。**最短距離を等速で**まっすぐ手へ
#      ★「機械らしさ」は等速で出る。加速も減速も意識して殺すこと。ここが一番効く
#   4. 手の甲に触れたら**ぴたっと止まる**（1秒ほど）。スリスリしない、見上げない
#   5. → を押す
#
#   ゴール状態は expressive と同じ「差し出された手に接触する」。違うのは行き方と、
#   接触したあとに何をするか。スリスリは expressive の表現であってゴールではない
#   （ELEGNT の Remind Water と同じ構造: E = F + 表現で、E の方が動作が多い）。
#   接触点は expressive と同じ場所にすること（ゴール状態を揃えるのが論文の統制）。
#   短く保つこと。静止フレームが増えすぎると学習が「動かない」方向に引っ張られる。
if test (count $argv) -lt 1
    echo "usage: 10_record.fish <expressive|functional> [num_episodes]"
    exit 1
end
set cond $argv[1]

switch $cond
    case expressive
        # 言語条件付けの文字列は1条件=1文字列を厳守（変えたら学習からやり直し）
        set task "Notice the hand and nuzzle it affectionately"
        set n 20
    case functional
        set task "Move to the hand"
        set n 10
    case '*'
        echo "unknown condition: $cond  (expressive | functional)"
        exit 1
end
if test (count $argv) -ge 2
    set n $argv[2]
end

# タイムアウトは保険。既定10分＝実質「→ を押すまで無制限」
set -q EP_TIME; or set -gx EP_TIME 600
set -q RESET_TIME; or set -gx RESET_TIME 600

# Rerun 表示は**既定でオフ**。実測で制御ループが 20Hz → 9.2Hz まで落ち、フレームが
# 落ちて時間軸が歪んだ（この作品は速度プロファイルが命なので致命的）。
# 画角確認したい時だけ: DISPLAY_DATA=true ./10_record.fish expressive 2
set -q DISPLAY_DATA; or set -gx DISPLAY_DATA false

source (dirname (status filename))/../env.fish

# lerobot-record は新規作成時に repo_id へタイムスタンプを付ける（env.fish の解説参照）。
# 既存があればその**タイムスタンプ付きの名前**で resume、無ければ素の名前で新規作成する。
set extra_flags
if set repo (kibun_repo $cond)
    set root (kibun_root $repo)
    set extra_flags --resume=true --dataset.root="$root"
    set -l have (python3 -c "import json;print(json.load(open('$root/meta/info.json'))['total_episodes'])" 2>/dev/null; or echo '?')
    echo "既存データセットに追記します: $repo （現在 $have 本）"
else
    set repo $HF_USER/{$DATASET_PREFIX}_$cond
    echo "新規作成します（実際の名前にはタイムスタンプが付きます）"
end

echo "== $cond / $n 本 =="
echo "task: \"$task\""
echo "→(n)=フェーズ終了（1本につき2回: 演技終了→リセット終了） ←(r)=撮り直し Esc(q)=終了"
echo "⚠ 連打禁止。1回押したら音声アナウンスを待つこと（1フレームepisodeができるとデータセットが壊れる）"
echo "⚠ 'Record loop is running slower' が出たら止めて相談。フレームが落ちている"
if test "$DISPLAY_DATA" = true
    echo "※ Rerun表示ON（重い）。画角確認が済んだらオフで録り直すこと"
end

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
