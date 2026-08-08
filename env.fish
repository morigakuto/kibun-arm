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
    # ★ auto にしてはいけない。この機体は NVIDIAドライバの版ずれ
    #   （カーネル 580.159.03 / NVML 580.173）で h264_nvenc が
    #   avcodec_open2 に失敗し、録画が Encoder thread crashed で落ちる。
    #   ソフトウェアの h264 を明示する。640x480@20fps なら十分速い。
    set -gx VCODEC h264
    # Linux は挿した順に /dev/ttyACM0, /dev/ttyACM1 が割り当てられる。
    # 2026-08-08 のロールアウトでは ttyACM0 がフォロワーとして動作した。
    # 逆だったら 01_teleop_check.fish で確認して入れ替えること。
    set -gx FOLLOWER_PORT /dev/ttyACM0
    set -gx LEADER_PORT   /dev/ttyACM1
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
