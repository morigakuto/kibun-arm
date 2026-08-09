#!/usr/bin/env fish
# 全カメラのライブ映像を横並びで表示する。カメラの位置決め用。
#   ./01_camera_live.fish
#   q または ESC で終了
#
# GUIウィンドウを出すので DISPLAY が必要。SSH越しのターミナルでは
# 設定されていないことがあるため、無ければ :2（このマシンのログインセッション）を使う。
# 別の番号なら: DISPLAY=:1 ./01_camera_live.fish
source (dirname (status filename))/../env.fish

if not set -q DISPLAY; or test -z "$DISPLAY"
    set -gx DISPLAY :2
    echo "DISPLAY が未設定だったので :2 を使います"
end
echo "DISPLAY=$DISPLAY  （ウィンドウが出ない場合は :1 も試してください）"
echo "ウィンドウ上で q または ESC を押すと終了します"

cd $LEROBOT_DIR
uv run python -c "
import cv2, re, sys, numpy as np
cams = '''$CAMERAS'''
entries = re.findall(r'(\w+):\s*\{[^}]*index_or_path:\s*([^,}]+)', cams)
if not entries:
    print('カメラ設定を解釈できませんでした'); sys.exit(1)

caps = []
for name, path in entries:
    path = path.strip()
    src = int(path) if path.isdigit() else path
    cap = cv2.VideoCapture(src)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640); cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    if not cap.isOpened():
        print(f'  ✗ 開けません: {name} ({path})')
    caps.append((name, cap))

print(f'  {len(caps)} 台を表示中...')
win = 'camera live  (q/ESC で終了)'
cv2.namedWindow(win, cv2.WINDOW_NORMAL)
try:
    while True:
        tiles = []
        for name, cap in caps:
            r, f = cap.read()
            if not r or f is None:
                f = np.zeros((480, 640, 3), np.uint8)
                cv2.putText(f, 'NO SIGNAL', (150, 250), cv2.FONT_HERSHEY_SIMPLEX, 2, (0,0,255), 3)
            else:
                f = cv2.resize(f, (640, 480))
            cv2.rectangle(f, (0,0), (640,40), (0,0,0), -1)
            cv2.putText(f, name, (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 1, (255,255,255), 2)
            tiles.append(f)
        cv2.imshow(win, np.hstack(tiles))
        k = cv2.waitKey(1) & 0xFF
        if k in (ord('q'), 27):
            break
finally:
    for _, c in caps: c.release()
    cv2.destroyAllWindows()
"
