# キャリブレーション

2026-08-08 に**このアーム**（借用機、tron-workstation に接続）で作成したもの。

## ⚠ これを必ず配置してから推論・録画すること

lerobot は `~/.cache/huggingface/lerobot/calibration/` にファイルが**無い場合、プロンプトも出さずに
いきなり再キャリブレーションを始める**（`robots/robot.py:55` の `if self.calibration_fpath.is_file()` が
偽 → `so_follower.py:116` の `if self.calibration:` も偽 → 即 `calibrate()` 実行）。

再キャリブレーションすると原点（homing_offset）が変わり、

- 学習済みポリシーの出力が**別の物理位置**にマッピングされる
- 録画済みエピソードと action 空間が食い違う

ので、22本の expressive も学習済みモデルも全部無駄になる。

## 配置（Linux / macOS 共通）

```bash
mkdir -p ~/.cache/huggingface/lerobot/calibration/robots/so_follower
mkdir -p ~/.cache/huggingface/lerobot/calibration/teleoperators/so_leader
cp follower.json ~/.cache/huggingface/lerobot/calibration/robots/so_follower/
cp leader.json   ~/.cache/huggingface/lerobot/calibration/teleoperators/so_leader/
```

`train/rollout_ubuntu.sh` は起動時にこれを自動でやる。

## 正しく効いているかの確認

接続時に

```
Press ENTER to use provided calibration file associated with the id follower, or type 'c' ...
```

と**プロンプトが出れば正常**（ファイルが読めている）。ここでは必ず **ENTER**。`c` を押すと上記の事故が起きる。

プロンプトが出ずにいきなり「Move to the middle of its range of motion」と言われたら、
ファイルが置けていない。即座に Ctrl-C して配置し直すこと。
