#!/usr/bin/env fish
# データセットの状態を一覧する。各エピソードの長さが出るので、切れている本を特定できる。
#   ./45_inspect.fish            → 全条件
#   ./45_inspect.fish expressive → 1条件だけ
source (dirname (status filename))/../env.fish

set conds $argv
if test (count $conds) -eq 0
    set conds expressive functional
end

cd $LEROBOT_DIR
for cond in $conds
    if not set repo (kibun_repo $cond)
        echo "== $cond : まだ録画なし"
        continue
    end
    set root (kibun_root $repo)
    echo "== $cond → $repo"
    uv run python -c "
import json, pathlib, pandas as pd
root = pathlib.Path('$root')
info = json.load(open(root/'meta/info.json'))
fps = info['fps']
print(f\"   合計 {info['total_episodes']} 本 / {info['total_frames']} フレーム / {fps} fps\")
files = sorted((root/'meta'/'episodes').rglob('*.parquet'))
if not files:
    raise SystemExit
df = pd.concat([pd.read_parquet(f) for f in files]).sort_values('episode_index')
for _, r in df.iterrows():
    sec = r['length'] / fps
    mark = ''
    if sec < 8:    mark = '  ← 短すぎ'
    elif sec > 55: mark = '  ← 長すぎ（尻に無音区間？）'
    print(f\"   ep {int(r['episode_index']):3d}: {sec:5.1f}s{mark}\")
"
end
