#!/usr/bin/env fish
# カメラを列挙してサンプル画像を保存する。
# 実行後 ~/cinaps/lerobot/outputs/captured_images を開き、
# どの index が wrist / top かを確認。env.fish の CAMERAS と食い違ったら直す。
source (dirname (status filename))/../env.fish
cd $LEROBOT_DIR
uv run lerobot-find-cameras opencv
