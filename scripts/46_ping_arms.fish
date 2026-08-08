#!/usr/bin/env fish
# 両アームの全モーターが応答するか確認する（読み出しのみ、アームは動かない）。
# `ConnectionError: ... There is no status packet!` で落ちた後、
# ハードが復帰したかを判断するために使う。
source (dirname (status filename))/../env.fish
cd $LEROBOT_DIR
uv run python -c "
from lerobot.motors.feetech import FeetechMotorsBus
from lerobot.motors import Motor, MotorNormMode
for name, port in [('follower','$FOLLOWER_PORT'), ('leader','$LEADER_PORT')]:
    motors = {f'm{i}': Motor(i, 'sts3215', MotorNormMode.RANGE_M100_100) for i in range(1,7)}
    bus = FeetechMotorsBus(port=port, motors=motors)
    try:
        bus.connect(handshake=False)
        ok = [i for i in range(1,7) if _ping(bus, i)] if False else []
        for i in range(1,7):
            try:
                bus.ping(i); ok.append(i)
            except Exception: pass
        if len(ok) == 6:
            print(f'{name:9s}: OK — 全6モーター応答')
        elif ok:
            print(f'{name:9s}: ⚠ 応答 {ok} / 欠け {sorted(set(range(1,7))-set(ok))}'
                  ' → 欠けた番号より先のデイジーチェーンを疑う')
        else:
            print(f'{name:9s}: ✗ 全滅 → 電源（バレルジャック）とコントローラ直近のケーブル')
        bus.disconnect()
    except Exception as e:
        print(f'{name:9s}: ✗ 接続失敗 {type(e).__name__}: {e}')
" 2>&1 | grep -v "^INFO\|^WARNING"
