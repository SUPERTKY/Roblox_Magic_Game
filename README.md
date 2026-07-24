# Roblox Magic Game

Roblox Studio で動く、プリセット魔法を使った対戦ゲームです。

## ゲーム内容

- ロビーの魔法ゲートに入ると、バトルフィールド内の安全なスポーン地点へランダム転送
- 3種類のプリセット魔法で対戦
  - `1` Fireball: 着弾地点の周囲にもダメージ
  - `2` Frost Bolt: 命中した相手を短時間スロー
  - `3` Arcane Bolt: 連射しやすい直線魔法
- PCは数字キーで魔法を選び、クリックで発射
- モバイルは画面下の魔法を選び、右側の「発射」ボタンで画面中央へ発射
- ダメージ、射程、クールダウンはすべてサーバー側で検証
- 倒されたプレイヤーはロビーから再スタート

## Roblox Studio で起動

1. [Rojo](https://rojo.space/) をインストールします。
2. このリポジトリで `rojo serve` を実行します。
3. Roblox Studio で新しい Baseplate を開き、Rojo プラグインから接続します。
4. Play を押すと、ロビー、ゲート、バトルフィールドが自動生成されます。

魔法の威力や色、射程、クールダウンは
`src/ReplicatedStorage/Shared/SpellDefinitions.luau` で変更できます。

## 構成

- `WorldBuilder.server.luau`: ロビー、ゲート、バトルフィールド、スポーン地点を生成
- `MagicBattle.server.luau`: ゲート転送、ランダムスポーン、魔法の命中・ダメージ処理
- `MagicController.client.luau`: 魔法選択、照準、PC/モバイル操作UI
- `SpellDefinitions.luau`: 事前に用意された魔法の共通設定

