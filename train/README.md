# 学習マシン（Ubuntu RTX 6000）での手順

## ★ ログインは一切不要

会社PCなどでアカウントを使いたくない場合、下記の構成で **GitHub も Hugging Face も wandb もログイン不要**。

| 必要なもの | ログイン | 理由 |
|---|---|---|
| `git clone` lerobot | **不要** | 公開リポジトリの HTTPS clone は匿名。アカウントもトークンもいらない |
| `uv` / `uv sync` | **不要** | PyPI は匿名 |
| データセット | **不要** | 公開設定（`private: False`）。または USB で持ち込めばDL自体が不要 |
| `lerobot/smolvla_base` | **不要** | 公開モデル |
| 学習結果の保存 | **不要** | `PUSH_TO_HUB=false`（既定）でローカルに保存 → USB で Mac へ戻す |
| 提出用の push | — | **Mac 側でやる**（既にログイン済み） |

「GitHubを使う」＝「GitHubにログインする」ではありません。公開リポジトリの clone は匿名でできます。

## 手順

### A. USB でデータも持ち込む（ネット依存が最小）

Mac 側で:

```fish
./scripts/50_prep_usb.fish /Volumes/<USB名>
```

学習マシン側で:

```bash
cd <USBのパス>/kibun
chmod +x train_remote.sh
DATA_ROOT=$PWD/datasets ./train_remote.sh act        # 条件別ACT×2、各30〜60分
DATA_ROOT=$PWD/datasets ./train_remote.sh smolvla    # 本命、3〜6時間
```

### B. データは HF から落とす（USBには train_remote.sh だけ）

```bash
./train_remote.sh act
./train_remote.sh smolvla
```

どちらも初回に lerobot を Mac と同一コミット（`0d383d09`）で clone + `uv sync` する（10分ほど）。

### スモークテスト（録画の途中で回すやつ）

```bash
STEPS=8000 ./train_remote.sh act expressive     # 約15分。「手に寄るか」だけ見る
```

## 学習結果を Mac へ戻す

`PUSH_TO_HUB=false` なのでチェックポイントはローカルに残る。実行後に場所が表示される。

```bash
cp -r ~/lerobot-kibun/outputs/train /media/<USB>/kibun-models/
```

Mac 側で実機確認（ローカルパスをそのまま渡せる）:

```fish
./scripts/40_rollout.fish /path/to/kibun-models/act_nuzzle_hand_v1_expressive/checkpoints/last/pretrained_model expressive 3
```

提出用に Hub へ上げるのも Mac から（Mac は既にログイン済み）:

```fish
cd ~/cinaps/lerobot
uv run hf upload TECHIdesu/act_nuzzle_hand_v1_expressive /path/to/pretrained_model .
```

第3引数の `.` はリポジトリ直下に置く指定。`pretrained_model/` の中身（config・重み）が
そのまま repo のルートに並ぶ形にすること。

## HF に直接 push したい場合（ログインしてよいなら）

```bash
hf auth login
PUSH_TO_HUB=true ./train_remote.sh all
```

生成物: `TECHIdesu/act_nuzzle_hand_v1_expressive` / `_functional`（保険）、
`TECHIdesu/smolvla_nuzzle_hand_v1_mixed`（本命）。

## 前提チェック

```bash
nvidia-smi     # ドライバ >= 570.86 か（lerobot は cu128 wheel）
```

## 時間が押したときの優先順位

1. ACT×2 だけで寝る（デモは成立する）
2. SmolVLA は `--batch_size=16` + `STEPS=10000` に縮めても条件分離の確認には十分
3. 学習マシンが使えない場合の代替: `level`（RTX 5080 16GB、空き）に ssh できる。
   前回 SmolVLA b16 を回した実績あり（`level:~/lerobot`）
