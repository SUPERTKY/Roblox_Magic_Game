# Roblox Magic Game

プレイヤーがロビーで既存の属性と戦闘スタイルを組み合わせ、名前を付けた本人専用のオリジナル魔法を作成して戦うRobloxゲームです。魔法はバトルグラウンド内でのみ使用できます。

## ゲームの流れ

1. ロビーで魔法名を入力
2. 現在ある属性から1つ選択
   - 炎: 爆発範囲が広がる
   - 氷: 命中した相手を短時間スロー
   - 魔力: ダメージが少し高くなる
3. 現在ある戦闘スタイルから1つ選択
   - 高威力型: 遅いが強力
   - バランス型: 威力・速度・クールダウンが平均的
   - 連射型: 低威力だが素早く連射可能
4. 選んだ「属性 × 戦闘スタイル」にプレイヤーが名前を付け、「この魔法を作成」を押して保存
5. 魔法ゲートに入ると、用意されたバトルグラウンド内のスポーン地点へ移動
6. 作成した本人専用の魔法で対戦

作成前のプレイヤーはゲートに入れません。倒されたプレイヤーはロビーへ戻りますが、作成した魔法は維持されます。ロビーやバトルグラウンドの外から発射リクエストを送っても、サーバー側で拒否されます。

## バトルグラウンドの設置

バトルグラウンド本体はこのリポジトリでは自動生成しません。作成したマップを、Roblox Studioの `Workspace` 直下に `BattleGround` という名前の `Model` または `Folder` として配置してください。

`BattleGround` の中には次を用意します。

- `BattleBounds`: 戦闘可能範囲全体を覆う `BasePart`
  - `Anchored = true`
  - `CanCollide = false`
  - `Transparency = 1` 推奨
- `BattleSpawnPoints`: スポーン地点をまとめる `Folder`
  - 中に1個以上の `BasePart` を置く
  - 各スポーン地点は `BattleBounds` の内側に置く

ゲートは `BattleBounds` とスポーン地点がそろっている場合だけプレイヤーを戦場へ送ります。発射時にもプレイヤーが `BattleBounds` 内にいるかサーバーが確認します。

## 崩れる建物

攻撃魔法が当たったときに崩したい建物は、建物全体を1つの `Model` にまとめ、次のどちらかを設定します。

- CollectionServiceのタグ `DestructibleBuilding` をModelへ付ける
- ModelのAttribute `DestructibleBuilding` をBooleanの `true` にする

魔法が建物へ直撃すると、Model内の `BasePart` の `Anchored` が解除され、着弾点から外向きと上向きに力が加わって崩れます。同じ建物に崩壊処理が重複して実行されることはありません。ロビー、`BattleBounds`、スポーン地点にはこのタグやAttributeを付けないでください。

## 操作

- PC: バトルグラウンド内でクリックすると、作成した魔法を発射
- モバイル: バトルグラウンド内で画面右側の「発射」ボタンを押すと、画面中央へ発射

## 保存と安全対策

- 魔法名・属性・戦闘スタイルをDataStoreへ保存
- DataStoreが利用できないStudioテストでも、そのセッション中は作成した魔法を使用可能
- プレイヤーが入力した魔法名はサーバー側でRobloxのテキストフィルターを適用
- 属性・スタイル・ダメージ・射程・クールダウンはサーバー側で検証
- クライアントからダメージ値や建物破壊フラグを送信できない設計
- 魔法の発射と対人ダメージは、攻撃側・対象側ともバトルグラウンド内にいる場合だけ有効

## Roblox Studio で起動

1. [Rojo](https://rojo.space/) をインストールします。
2. このリポジトリで `rojo serve` を実行します。
3. Roblox Studioでゲームを開き、Rojoプラグインから接続します。
4. `Workspace.BattleGround` と、その中の `BattleBounds`・`BattleSpawnPoints` を用意します。
5. 崩したい建物へ `DestructibleBuilding` タグまたはAttributeを設定します。
6. Playを押すと、ロビーとゲートが自動生成されます。

公開ゲームで保存を使用する場合は、Roblox StudioのGame SettingsからAPI Servicesを有効にしてください。

## 現在のスクリプト構成

- `WorldBuilder.server.luau`: ロビー、作成案内、ゲートを生成し、持ち込みバトルグラウンドの必須構成を確認
- `MagicBattle.server.luau`: オリジナル魔法の作成・保存・読込、ゲート転送、戦場内判定、戦闘、建物崩壊を処理
- `MagicController.client.luau`: ロビーの魔法作成画面、照準、PC・モバイル操作UI
- `SpellDefinitions.luau`: 選択可能な属性と戦闘スタイル、能力値の合成規則、攻撃魔法の建物破壊可否
