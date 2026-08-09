#!/usr/bin/env fish
# ★録画前に必ず実行すること★
# env.fish で設定した全カメラから1枚ずつ取得し、1枚の画像に並べて保存する。
# 「3台とも映っているか」「どれがどの視点か」「カードとキューブが写っているか」を
# 目で確認してから録画に入る。
#
#   ./00_check_cameras.fish
#
# 2026-08-09 の失敗: 手首カメラ1台しか録れておらず、把持・運搬中はカードが
# 画角外だった。26本を録り終えてから気づいた。この確認を挟めば防げる。
source (dirname (status filename))/../env.fish

set out $HOME/camera_check.png
set tmpdir /tmp/camcheck
rm -rf $tmpdir; mkdir -p $tmpdir

echo "== 設定されているカメラ =="
echo $CAMERAS | tr ',' '\n' | grep -oE '^\s*\{?[a-z_]+:' | tr -d ' {:' | sed 's/^/  - /'

cd $LEROBOT_DIR
uv run python -c "
import cv2, re, sys, pathlib, numpy as np
cams = '''$CAMERAS'''
# {name: {..., index_or_path: X, ...}} を素朴に抽出
entries = re.findall(r'(\w+):\s*\{[^}]*index_or_path:\s*([^,}]+)', cams)
if not entries:
    print('カメラ設定を解釈できませんでした'); sys.exit(1)

tiles, ok, ng = [], [], []
for name, path in entries:
    path = path.strip()
    src = int(path) if path.isdigit() else path
    cap = cv2.VideoCapture(src)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640); cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    frame = None
    for _ in range(10):
        r, f = cap.read()
        if r: frame = f
    cap.release()
    if frame is None:
        ng.append(name)
        frame = np.zeros((480, 640, 3), np.uint8)
        cv2.putText(frame, 'NO SIGNAL', (150, 250), cv2.FONT_HERSHEY_SIMPLEX, 2, (0,0,255), 3)
    else:
        ok.append(name)
        frame = cv2.resize(frame, (640, 480))
    cv2.rectangle(frame, (0,0), (640,40), (0,0,0), -1)
    cv2.putText(frame, name, (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (255,255,255), 2)
    tiles.append(frame)

cv2.imwrite('$out', np.hstack(tiles))
print()
print('  映った:', ', '.join(ok) if ok else 'なし')
if ng:
    print('  ✗ 映らない:', ', '.join(ng))
    print('  → USBを挿し直すか env.fish の by-id パスを確認すること')
    sys.exit(1)
"
set rc $status

echo ""
if test $rc -eq 0
    echo "✓ 全カメラ確認: $out"
else
    echo "✗ 映らないカメラがあります。録画に入らないでください"
end
echo ""
echo "画像を開く:  xdg-open $out"
echo "Macへ送る（Mac側で）:  rsync -avh tron:$out ~/Desktop/"
echo ""
echo "確認すること:"
echo "  1) 3枚とも映っているか"
echo "  2) どれか1枚で、鬼カードが**全フェーズを通して**画角に入るか"
echo "     （手首カメラだけだと把持・運搬中にカードが見えない）"
echo "  3) キューブと巣（器）が映っているか"
exit $rc
