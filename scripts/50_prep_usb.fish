#!/usr/bin/env fish
# USBメモリに、学習マシンで必要なものを全部まとめる。
# 会社PCにどこにもログインせずに学習を回すための経路。
#
#   ./50_prep_usb.fish /Volumes/<USB名>
#
# コピーされるもの:
#   <USB>/kibun/train_remote.sh              学習スクリプト
#   <USB>/kibun/README.md                    手順
#   <USB>/kibun/datasets/nuzzle_hand_v1_*    データセット（きれいな名前にリネームして）
#
# 学習マシン側:
#   cd /path/to/usb/kibun
#   chmod +x train_remote.sh
#   DATA_ROOT=$PWD/datasets ./train_remote.sh act
if test (count $argv) -lt 1
    echo "usage: 50_prep_usb.fish <コピー先> (例: /Volumes/USBSTICK)"
    echo ""
    echo "接続中のボリューム:"
    ls -1 /Volumes/ | sed 's/^/  \/Volumes\//'
    exit 1
end
set dest $argv[1]/kibun

if not test -d $argv[1]
    echo "コピー先が見つかりません: $argv[1]"
    exit 1
end

source (dirname (status filename))/../env.fish
set here (dirname (status filename))/..

mkdir -p $dest/datasets
cp $here/train/train_remote.sh $dest/
cp $here/train/README.md $dest/
chmod +x $dest/train_remote.sh

for cond in expressive functional mixed
    if not set repo (kibun_repo $cond)
        # mixed はタイムスタンプが付かないので直接見る
        set -l direct $HOME/.cache/huggingface/lerobot/$HF_USER/{$DATASET_PREFIX}_$cond
        if test -d $direct
            set repo $HF_USER/{$DATASET_PREFIX}_$cond
        else
            echo "skip (未収録): $cond"
            continue
        end
    end
    set src (kibun_root $repo)
    set dst $dest/datasets/{$DATASET_PREFIX}_$cond
    echo "コピー中: $cond ("(du -sh $src | cut -f1)")"
    rm -rf $dst
    cp -R $src $dst
end

echo ""
echo "完了: $dest"
du -sh $dest
echo ""
echo "学習マシンでの実行:"
echo "  cd <USBのパス>/kibun"
echo "  chmod +x train_remote.sh"
echo "  DATA_ROOT=\$PWD/datasets ./train_remote.sh act"
