# Lobby Magic V2

ロビーで魔法を作り、ゲートからグラウンドへ出て戦い、帰還するための最小システムです。

最初の版では次の魔法だけ作成できます。

> 火 × 生成 × 敵 × 自分から出す × クリック・タップ地点へ投げて爆発

完成名は **ファイアボム** です。

## 旧システムとの分離

新システムはすべて次の名前に分離されています。

- `ReplicatedStorage/LobbyMagicV2`
- `ServerScriptService/LobbyMagicV2`
- `Workspace/LMV2_World`
- `Workspace/LMV2_Runtime`
- `StarterPlayerScripts/LMV2Client`
- `StarterPlayerScripts/LMV2UI`
- Player属性はすべて `LMV2_` から開始

旧 `Magic`、`Remotes`、`SpellClient`、`FireballServer`、`FireballClient` は呼び出しません。

唯一の例外として、`RobloxMagicSystem/InstallRobloxMagicSystem.lua` がStudioに作成する次の炎エフェクトテンプレートを、見た目だけ複製して使います。

```text
ReplicatedStorage
└─ FireballVFX
   └─ Templates
      ├─ Projectile (BasePart)
      ├─ Cast (BasePart)
      └─ Explosion (BasePart)
```

旧 `FireballVFX` のModuleScriptやRemoteEventは実行しません。`Projectile`、`Cast`、`Explosion`の3テンプレートは必須です。簡易VFXへの切り替えは行いません。

### 炎VFXの準備

1. StudioのPlayテストを停止します。
2. `RobloxMagicSystem/InstallRobloxMagicSystem.lua` 冒頭の `TEXTURE_IDS` に4枚の画像IDを設定します。
3. スクリプト全体をStudioのCommand Barで実行します。
4. `ReplicatedStorage/FireballVFX/Templates` に `Projectile`、`Cast`、`Explosion` が作成されたことを確認します。
5. 新システムだけで操作する場合は、インストーラーが追加した旧 `FireballServer` と `FireballClient` を無効化します。`ReplicatedStorage/FireballVFX` は残します。

炎VFXが不足している場合、Lobby Magic V2はマナを消費せず発動を拒否し、OutputとUIへ不足パスを表示します。

発射時の一回限りの粒子と着弾爆発は、`VFXEvent`を受け取った各クライアントがローカルで `Emit()` します。StudioではServer表示ではなくClient表示で確認してください。飛行中のProjectileとダメージ判定は引き続きサーバーが管理します。

## Studioで作成する3D構造

`Workspace`へ次の構造を**完全一致の名前**で作成してください。6個の中身はすべて `Part`、`MeshPart`、`SpawnLocation`などの `BasePart` にします。

```text
Workspace
└─ LMV2_World (Folder または Model)
   ├─ LobbySpawn (BasePart)
   ├─ GroundSpawn (BasePart)
   ├─ ForgeConsole (BasePart)
   ├─ ForgeUIZone (BasePart)
   ├─ ExitGate (BasePart)
   └─ ReturnGate (BasePart)
```

| 名前 | 役割 | 推奨設定 |
|---|---|---|
| `LobbySpawn` | 参加・敗北・帰還時の位置 | `Anchored=true`。見せない場合は透明化 |
| `GroundSpawn` | 出撃時の位置 | `Anchored=true`。床より少し上へ配置 |
| `ForgeConsole` | 最初の炎魔法を作る場所 | プレイヤーが12stud以内へ近づける場所 |
| `ForgeUIZone` | 設定UIを表示する範囲 | `Anchored=true`、`CanCollide=false`、`Transparency=1`。工房を覆う大きさにする |
| `ExitGate` | ロビーからグラウンドへ出る場所 | プレイヤーが12stud以内へ近づける場所 |
| `ReturnGate` | グラウンドからロビーへ戻る場所 | グラウンド側へ配置 |

`ForgeConsole`、`ExitGate`、`ReturnGate`には、サーバースクリプトが次の `ProximityPrompt` を自動追加します。手動でPromptを作る必要はありません。

```text
ForgeConsole/LMV2_ForgePrompt
ExitGate/LMV2_ExitPrompt
ReturnGate/LMV2_ReturnPrompt
```

名前を変更したい場合は `Shared/LMV2Config.lua` の `World` を変更してください。スクリプト内へ座標を直接書く必要はありません。

## 導入方法

Rojoでこのプロジェクトだけを同期します。

```bash
rojo serve LobbyMagicV2/default.project.json
```

StudioのRojoプラグインから接続したあと、Playテストを開始してください。

旧プロジェクトの `RobloxMagicSystem/default.project.json` と同時に同期する必要はありません。既にStudioに旧システムが入っていても、新システムの名前とRemoteは衝突しません。同じ入力で旧魔法まで発動しないように、旧 `FireballClient` / `SpellClient` は無効化してください。炎VFXの `ReplicatedStorage/FireballVFX/Templates` は必ず残します。

## UIなしでのゲーム進行

`Shared/LMV2Config.lua` の次を `false` にすると、自動生成UIを停止できます。

```lua
EnableGeneratedUI = false
```

UIが無くても次の操作は残ります。

1. `ForgeConsole`のPromptで炎魔法を作る
2. `ExitGate`のPromptでグラウンドへ出る
3. PCは左クリックまたは`F`、ゲームパッドは`R2`で発動。スマホは画面をタップして狙い、`FIRE`ボタンで発動
4. `ReturnGate`のPromptでロビーへ戻る

`LMV2UI.client.lua`は画面表示だけを担当します。削除してもサーバー処理や魔法入力は停止しません。

## 設定UIの表示範囲

設定UIはロビーにいるだけでは表示されません。プレイヤーの `HumanoidRootPart` が `ForgeUIZone` の箱型範囲内へ入ったときだけ表示され、外へ出ると閉じます。回転させた `ForgeUIZone` にも対応します。

`ForgeUIZone` が無くても、`ForgeConsole` のPromptから既定設定の魔法を作れるため、UIなしの進行は止まりません。

## 生成UIに含まれるもの

Studioで `ScreenGui` を作成する必要はありません。`LMV2UI.client.lua`が次を生成します。

- ロビーの進行表示「魔法作成 → 出撃 → バトル」
- 属性・生成方法・対象・発生場所・攻撃方法の左右切替
- 選択中のファイアボム設定表示
- マナ・クールダウンの足し算表示
- 「炎魔法を作る」ボタン
- 「グラウンドへ出る」ボタン
- 戦闘中のマナゲージ
- クールダウン・マナ不足・発動可能表示
- 成功・エラーの一時メッセージ

現在は各項目に1個の選択肢しかありません。左右ボタンは表示され、押すと「現在1種類だけ」と案内します。`LMV2SpellCatalog.lua` の `Components` と `OptionOrder` に選択肢を追加すると、同じUIで循環切替できます。

3D側のPromptと同じサーバー関数を使うため、UIからだけ特別な処理は行いません。

## 別のUIへ交換するときに必要な接続

自作UIは `ReplicatedStorage/LobbyMagicV2/Remotes` の次だけを使います。

| Remote | 方向 | 内容 |
|---|---|---|
| `LobbyActionRequest` | Client → Server | `{ Action = "CreateSpell", Selection = {...} }`、`"EnterGround"`、`"ReturnLobby"` |
| `CastSpellRequest` | Client → Server | `{ AimPosition = Vector3 }`。数値は送らない |
| `VFXEvent` | Server → Client | `Cast`・`Explosion`の位置。クライアント側で一回限りのParticleを発生 |
| `StateChanged` | Server → Client | 現在の状態・魔法・マナなどのSnapshot |
| `Feedback` | Server → Client | `{ Code, Message, ServerTime }` |
| `GetSnapshot` | Client → Server | 初回表示用のSnapshotを取得 |

UI表示にはPlayerの次の属性も利用できます。

| 属性 | 型 | 意味 |
|---|---|---|
| `LMV2_State` | string | `Lobby` または `Ground` |
| `LMV2_HasExampleSpell` | boolean | 炎魔法を作成済みか |
| `LMV2_SpellKey` | string | 装備中の魔法ID |
| `LMV2_Mana` | number | 現在マナ |
| `LMV2_MaxMana` | number | 最大マナ |
| `LMV2_CooldownEnd` | number | `Workspace:GetServerTimeNow()`基準の終了時刻 |
| `LMV2_SelectedAttribute` | string | 選択中の属性 |
| `LMV2_SelectedCreation` | string | 選択中の生成方法 |
| `LMV2_SelectedTarget` | string | 選択中の対象 |
| `LMV2_SelectedOrigin` | string | 選択中の発生場所 |
| `LMV2_SelectedAttack` | string | 選択中の攻撃方法 |

クライアントからマナ消費、ダメージ、爆発半径、クールダウンを送らないでください。サーバーが固定定義から再計算します。

## 最初の魔法の計算

| 設定 | マナ | クールダウン |
|---|---:|---:|
| 基本 | 5 | 1.0秒 |
| 火 | +8 | +0.5秒 |
| 生成 | +6 | +0.4秒 |
| 敵 | +4 | +0.2秒 |
| 自分から | +0 | +0秒 |
| 指定地点へ投げて爆発 | +14 | +1.4秒 |
| 合計 | **37** | **3.5秒** |

戦闘値は現在、ダメージ25・爆発半径12stud・最大距離145studです。変更先は `LMV2SpellCatalog.lua` です。

## 敵NPCの作り方

爆発対象にしたいNPCは通常のHumanoid構造にします。マップ内のどこに置いても構いません。

```text
EnemyDummy (Model)
├─ Humanoid
└─ HumanoidRootPart
```

同じチームへ攻撃させたくない場合は、PlayerまたはCharacter/NPC Modelへ文字列属性 `LMV2_Team` を設定します。同じ値同士は味方です。Robloxの `Team` が同じプレイヤー同士も味方として扱います。

## テスト手順

1. Play開始時に `LobbySpawn`へ移動する
2. `ForgeUIZone`の外では設定UIが非表示、内側では表示される
3. 5項目の左右ボタンが表示され、現在1種類だけという案内が出る
4. 工房PromptまたはUIでファイアボムを作る
5. 表示がマナ37・クールダウン3.5秒になる
6. ExitGateから`GroundSpawn`へ移動する
7. StudioのClient表示で、発射時と着弾時のエフェクトが表示される
8. 敵NPCの近くを狙って発動し、火球が指定地点または障害物で爆発する
9. 半径内の敵だけが25ダメージを受ける
10. マナ不足・クールダウン中はサーバーに拒否される
11. ReturnGateでLobbySpawnへ戻る
12. グラウンドで倒された場合も次のRespawnでロビーへ戻る

## 今回まだ入れていないもの

- 複数種類の魔法選択
- DataStoreへの魔法保存
- マッチメイキング、ラウンド時間、勝敗
- 魔法編集の複数選択UI

これらを追加するときも、`LMV2SpellCatalog`へ選択肢を増やし、サーバー側で最終値を組み立てる形を維持できます。
