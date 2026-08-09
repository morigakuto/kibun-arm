#!/usr/bin/env fish
# テレオペ練習セッション（録画なし）。録画前にこれで15〜20分練習する。
#
# ■ 確認その1: ポート割当
#   リーダー（手に持つ方）を動かしてフォロワーが追従すればOK。
#   逆に「手に持った方が固い／卓上の方が脱力して動かない」なら
#   env.fish の FOLLOWER_PORT と LEADER_PORT を入れ替えて再実行。
#
# ■ 確認その2: 画角
#   手を置く全域（3x3グリッド × 高さ2段）が映るか。映らない位置があるなら
#   カメラを動かすか、ワークスペースを狭める。
#
# ■ 練習その1: 「気づく」= 溜めの正体  ★これが作品の出来を決める
#   ELEGNT §3.2.2 (Intention): ロボットは対象に向かう前に、まず頭だけをそちらへ向ける。
#   これが意図の表明であり、注意の移動を人に伝える。
#   → 手が現れたら (1) 頭(手首)だけ手の方へ 0.3〜0.5秒で向ける → (2) 一拍おく → (3) 体が動き出す
#   いきなり全身で動き出さないこと。「溜め」は間ではなく、頭を先に向ける動作そのもの。
#
# ■ 練習その2: アイドルは「探している」動き
#   ELEGNT §5.2.1: 動かないロボットは "kinda creepy, as if it was intently staring"。
#   ELEGNT §5.2.3: 理由のない動きは "a lack of attention on the robot's part" に見える。
#   → 完全静止もダメ、ランダムなフラフラもダメ。ゆっくり左右を見渡す「捜索」の動き。
#     一貫した動きの方が学習も安定する。
#
# ■ 練習その3: スリスリ
#   押し込まず「沿わせる」。wrist roll を使った頬ずりが一番それらしい。グリッパは常時閉。
#   リーダーに力覚はないので、自分の手の甲で10分やって力加減を体で覚える。
#
# ■ 練習その4: 追従
#   スリスリ中に手をゆっくり動かし、ついていく。ELEGNT §5.2.3 は
#   「能力と動きのミスマッチは即座に嘘に見える」と指摘（P20: 頭にカメラが無いと思ったので
#   "メモを見る" 動作が嘘くさかった）。追えないのに追うふりは厳禁。だから実際に追従を仕込む。
#
# ■ rerun-sdk が無いと ImportError で落ちる。画角確認には表示が要るので入れること:
#     cd ~/lerobot-kibun
#     uv sync --locked --python 3.12 --extra training --extra smolvla --extra feetech --extra viz
#   ※ uv sync は環境を作り直すので extra は全部並べる（--extra viz だけだと他が消える）
#   表示なしで動作だけ見たい場合: DISPLAY_DATA=false ./01_teleop_check.fish
source (dirname (status filename))/../env.fish
set -q DISPLAY_DATA; or set -gx DISPLAY_DATA true
# rerun の表示先。Ubuntu機はGPUドライバの版ずれでローカル表示が落ちるため、
# Mac側のビューアへ Tailscale 経由で送る（Macで先に起動しておくこと）:
#   cd ~/cinaps/lerobot && uv run rerun --bind 0.0.0.0 --port 9876
set display_args
if test (uname) != Darwin -a "$DISPLAY_DATA" = true
    set -q DISPLAY_IP; or set -gx DISPLAY_IP 100.94.6.25
    set -q DISPLAY_PORT; or set -gx DISPLAY_PORT 9876
    set display_args --display_ip=$DISPLAY_IP --display_port=$DISPLAY_PORT
    echo "rerun の表示先: $DISPLAY_IP:$DISPLAY_PORT （Mac側のビューア）"
end
cd $LEROBOT_DIR
uv run lerobot-teleoperate \
    --robot.type=so101_follower \
    --robot.port="$FOLLOWER_PORT" \
    --robot.id="$FOLLOWER_ID" \
    --teleop.type=so101_leader \
    --teleop.port="$LEADER_PORT" \
    --teleop.id="$LEADER_ID" \
    --robot.cameras="$CAMERAS" \
    --fps=$FPS \
    --display_data=$DISPLAY_DATA \
    $display_args
