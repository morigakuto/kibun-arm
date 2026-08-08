#!/usr/bin/env fish
# 失敗エピソードの削除（in-place）。
#   使い方: ./20_delete_episodes.fish expressive "[0, 1, 2]"
#   エピソード番号の確認: ./45_inspect.fish expressive
#
# ⚠ lerobot-edit-dataset は編集前に元ディレクトリを `<名前>_old` にリネームして
#   バックアップを作る。成功すれば新しい方が正、失敗すると `_old` だけが残る。
#   `_old` は kibun_repo の候補から除外してあるので、残っていても後続の録画には影響しない。
#   確認後に消してよい: rm -rf ~/.cache/huggingface/lerobot/TECHIdesu/*_old
if test (count $argv) -lt 2
    echo "usage: 20_delete_episodes.fish <expressive|functional> \"[idx, idx, ...]\""
    exit 1
end
set cond $argv[1]
set eps $argv[2]

source (dirname (status filename))/../env.fish
if not set repo (kibun_repo $cond)
    echo "データセットが見つかりません: $cond"
    exit 1
end
set root (kibun_root $repo)

# 全部消そうとすると lerobot 側が ValueError で止まる（かつ `_old` へのリネームだけ残る）ので、
# 先にこちらで弾いて、代わりの手順を案内する。
set total (uv run --directory $LEROBOT_DIR python -c "import json;print(json.load(open('$root/meta/info.json'))['total_episodes'])" 2>/dev/null)
set n_del (echo $eps | tr ',' '\n' | grep -c '[0-9]')
if test -n "$total" -a "$n_del" -ge "$total" 2>/dev/null
    echo "⚠ $total 本中 $n_del 本 = 全部を消そうとしています。lerobot は空のデータセットを作れません。"
    echo "   全部捨てたい場合はディレクトリごと退避してください（次の録画で新規作成されます）:"
    echo "     mv $root {$root}_discarded"
    exit 1
end

echo "削除対象: $repo の $eps （現在 $total 本）"

cd $LEROBOT_DIR
uv run lerobot-edit-dataset \
    --repo_id="$repo" \
    --root="$root" \
    --operation.type=delete_episodes \
    --operation.episode_indices="$eps"
