#!/usr/bin/env fish
# データセットの動画をエピソード単位のmp4に切り出す（スライド・デモ動画用）。
#
#   ./60_export_clips.fish <データセットのパス> [出力先] [エピソード番号...]
#
#   例:
#     # 全エピソードを切り出す
#     ./60_export_clips.fish ~/.cache/huggingface/lerobot/TECHIdesu/daruma_v1_20260809_104208
#     # 3本だけ
#     ./60_export_clips.fish ~/.cache/.../daruma_v1_20260809_104208 ~/clips 0 5 12
#
# lerobot は複数エピソードを1つのmp4に連結して保存し、meta/episodes の
# from_timestamp / to_timestamp で範囲を持っている。ここではそれを見て ffmpeg で切る。
source (dirname (status filename))/../env.fish

if test (count $argv) -lt 1
    echo "usage: 60_export_clips.fish <データセットのパス> [出力先] [ep番号...]"
    echo ""
    echo "利用可能なデータセット:"
    ls -d $HOME/.cache/huggingface/lerobot/$HF_USER/*/ 2>/dev/null | sed 's|^|  |'
    exit 1
end

set root $argv[1]
set outdir $HOME/clips
if test (count $argv) -ge 2
    set outdir $argv[2]
end
set eps $argv[3..-1]

if not test -f $root/meta/info.json
    echo "データセットではありません: $root"
    exit 1
end

mkdir -p $outdir
cd $LEROBOT_DIR
uv run python -c "
import pandas as pd, pathlib, subprocess, sys, json
root = pathlib.Path('$root')
outdir = pathlib.Path('$outdir')
want = [int(x) for x in '''$eps'''.split()] or None

df = pd.concat([pd.read_parquet(p) for p in sorted((root/'meta/episodes').rglob('*.parquet'))]).sort_values('episode_index')
vkeys = sorted({c.split('/')[1] for c in df.columns if c.startswith('videos/')})
name = root.name

for cam in vkeys:
    ci, fi = f'videos/{cam}/chunk_index', f'videos/{cam}/file_index'
    ts0, ts1 = f'videos/{cam}/from_timestamp', f'videos/{cam}/to_timestamp'
    for _, r in df.iterrows():
        ep = int(r['episode_index'])
        if want is not None and ep not in want:
            continue
        src = root/'videos'/cam/f'chunk-{int(r[ci]):03d}'/f'file-{int(r[fi]):03d}.mp4'
        # カメラ名をファイル名に入れないと、3カメラが同じ名前で上書きし合う
        short = cam.replace('observation.images.', '')
        dst = outdir/f'{name}_ep{ep:03d}_{short}.mp4'
        dur = float(r[ts1]) - float(r[ts0])
        cmd = ['ffmpeg','-v','error','-y','-ss',str(float(r[ts0])),'-t',str(dur),
               '-i',str(src),'-c:v','libx264','-crf','20','-pix_fmt','yuv420p',str(dst)]
        subprocess.run(cmd, check=True)
        print(f'  ep {ep:3d}: {dur:5.1f}s -> {dst.name}')
"

echo ""
echo "出力先: $outdir"
ls -la $outdir | tail -5
echo ""
echo "Mac へ持ってくる（Mac側で実行）:"
echo "  rsync -avh tron:$outdir/ ~/Desktop/kibun-clips/"
