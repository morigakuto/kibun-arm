# きぶんのあるアーム — プロジェクト設定 (fish)
# 使い方: source env.fish   (各スクリプトは自動で source する)

set -gx HF_USER TECHIdesu
set -gx FOLLOWER_ID follower
set -gx LEADER_ID leader

# ── マシンごとの設定（Mac / Ubuntu 両方で同じスクリプトが動くように）──────
if test (uname) = Darwin
    # --- Mac（録画専用機）---
    set -gx LEROBOT_DIR $HOME/cinaps/lerobot
    # auto → h264_videotoolbox（動作実績あり。既存22本もこれで録った）
    set -gx VCODEC auto
    # USBの挿し位置を変えるとポート名が変わる。2026-08-08 検出値。
    # どちらがリーダーかは 01_teleop_check.fish で確認し、逆なら入れ替える。
    set -gx FOLLOWER_PORT /dev/tty.usbmodem5B3D0420591
    set -gx LEADER_PORT   /dev/tty.usbmodem5B3D0474411
else
    # --- Ubuntu (tron-workstation, RTX PRO 6000) ---
    set -gx LEROBOT_DIR $HOME/lerobot-kibun
    # ── カメラ3台（by-id の不変パス。/dev/video* の番号は挿し直しでずれる）──
    # 2026-08-09 の失敗: index 0 の1台（手首）しか録っておらず、把持・運搬中は
    # カードが画角外で「鬼が見えない」データになっていた。必ず3台とも録ること。
    # 録画前に必ず ./scripts/00_check_cameras.fish で3枚とも映っているか目視する。
    set -l cam /dev/v4l/by-id
    set -gx CAM_WRIST $cam/usb-Innomaker_Innomaker-U20CAM-1080p-S1_SN0001-video-index0
    set -gx CAM_FRONT $cam/usb-046d_HD_Pro_Webcam_C920-video-index0
    set -gx CAM_SIDE  $cam/usb-Global_Shutter_Camera_Global_Shutter_Camera_01.00.00-video-index0
    set -gx CAMERAS "{wrist: {type: opencv, index_or_path: $CAM_WRIST, width: 640, height: 480, fps: 30}, front: {type: opencv, index_or_path: $CAM_FRONT, width: 640, height: 480, fps: 30}, side: {type: opencv, index_or_path: $CAM_SIDE, width: 640, height: 480, fps: 30}}"

    # ★ auto にしてはいけない。この機体は NVIDIAドライバの版ずれ
    #   （カーネル 580.159.03 / NVML 580.173）で h264_nvenc が
    #   avcodec_open2 に失敗し、録画が Encoder thread crashed で落ちる。
    #   ソフトウェアの h264 を明示する。640x480@20fps なら十分速い。
    set -gx VCODEC h264
    # ★ /dev/ttyACM0,1 は挿し直すたびに番号が変わる（実際 2026-08-09 に ttyACM1,2 へずれて
    #   "No such file or directory: /dev/ttyACM0" で落ちた）。
    #   /dev/serial/by-id/ はシリアル番号ベースで不変なので、そちらを優先して使う。
    #   末尾の数字は Mac 側のポート名（...5B3D0420591 / ...5B3D0474411）と同じ個体を指す。
    set -l by_id /dev/serial/by-id
    if test -e $by_id/usb-1a86_USB_Single_Serial_5B3D042059-if00
        set -gx FOLLOWER_PORT $by_id/usb-1a86_USB_Single_Serial_5B3D042059-if00
        set -gx LEADER_PORT   $by_id/usb-1a86_USB_Single_Serial_5B3D047441-if00
    else
        # by-id が無い環境向けのフォールバック（番号は都度確認すること）
        set -gx FOLLOWER_PORT /dev/ttyACM0
        set -gx LEADER_PORT   /dev/ttyACM1
    end
    # uv は ~/.local/bin にある。fish の PATH に無いことがあるので通す
    if not contains $HOME/.local/bin $PATH
        set -gx PATH $HOME/.local/bin $PATH
    end
end

# ── カメラ ────────────────────────────────────────────────────
# 2026-08-08 13:33 実測（00_find_cameras.fish の結果）:
#   index 0 = Innomaker 外付け (1920x1080@30) ← 使える。唯一の外付け
#   index 1 = MacBook内蔵カメラ (@15fps)      ← 顔と天井が映る。学習に使うと壊れる
#   index 2 = iPhone Continuity (@1fps, 真っ黒) ← 未接続状態
# 2台目の外付けをつないだら 00_find_cameras.fish で index を再確認すること。

# --- A) 2カメラ構成（推奨。2台目をつないでから index を実測して直す）---
# set -gx CAMERAS '{wrist: {type: opencv, index_or_path: 0, width: 640, height: 480, fps: 30}, side: {type: opencv, index_or_path: 3, width: 640, height: 480, fps: 30}}'

# --- B) 1カメラ構成（今すぐ録るならこれ。外付け1台だけ）---
# 手の出現と接近が一番よく見える位置に固定すること（真横 or 斜め上前方）。
set -gx CAMERAS '{side: {type: opencv, index_or_path: 0, width: 640, height: 480, fps: 30}}'

set -gx FPS 20
set -gx DATASET_PREFIX nuzzle_hand_v1
# データセット名: TECHIdesu/nuzzle_hand_v1_{expressive,functional} と _mixed（統合）

# ── データセット名の解決 ──────────────────────────────────────
# 重要: lerobot-record は新規作成時に repo_id へ **タイムスタンプを自動で付ける**
# （configs/dataset.py の stamp_repo_id）。resume 時は付けない。
# したがって実際のデータセットは nuzzle_hand_v1_expressive_20260808_151839 のような名前になる。
# この関数で「その条件の最新のデータセット」を解決する。無ければ何も返さず 1 を返す。
function kibun_repo --description "条件名から最新のタイムスタンプ付き repo_id を返す"
    set -l cond $argv[1]
    set -l base $HOME/.cache/huggingface/lerobot/$HF_USER
    # fish の glob は不一致時にエラーを出すので find に展開させる。
    # lerobot-edit-dataset は in-place 編集の前に元を `_old` へリネームしてバックアップするので、
    # それは候補から除外する（拾うと古いデータに resume してしまう）。
    set -l found (find $base -maxdepth 1 -type d -name "$DATASET_PREFIX"_"$cond"_'*' ! -name '*_old' 2>/dev/null | sort)
    # 作成直後にクラッシュしたデータセットはディレクトリだけ残り meta/tasks.parquet が無い。
    # それに --resume すると、ローカルに読めるものが無いので HF Hub に問い合わせに行き、
    # 未ログインだと 401 RepositoryNotFoundError で落ちる。中身のあるものだけを候補にする。
    set -l valid
    for d in $found
        if test -f $d/meta/info.json -a -f $d/meta/tasks.parquet
            set -a valid $d
        end
    end
    if test (count $valid) -eq 0
        return 1
    end
    # 名前末尾が YYYYmmdd_HHMMSS なので辞書順ソートの最後が最新
    echo $HF_USER/(basename $valid[-1])
end

function kibun_root --description "repo_id からローカルの root パスを返す"
    echo $HOME/.cache/huggingface/lerobot/$argv[1]
end
