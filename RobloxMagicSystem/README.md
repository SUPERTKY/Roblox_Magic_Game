# Roblox Magic System

「属性 × 出し方 × 攻撃形態」をサーバー権威型で組み合わせる、Roblox用の魔法システムです。

## 実装済み

### 属性

- 火：燃焼、継続ダメージ
- 氷：減速、3ヒットで凍結
- 雷：感電による一時減速、最大3体への連鎖
- 風：`BasePart:ApplyImpulse()` による吹き飛ばし
- 毒：継続ダメージ
- 光：味方・自分を回復、弾系スペルは複数対象を貫通

### 出し方

- 投げる：狙った方向へサーバー管理の弾を飛ばす
- 置く：照準地点の地面へ設置
- 自分から出す：プレイヤー中心で発生。持続範囲はプレイヤーを追従
- 空中に出す：照準地点の上空に生成
- 地面から出す：地面位置へ生成し、地面発生エフェクトを表示

### 攻撃形態

- 爆発：範囲攻撃
- 拡散：扇状または全方向へ複数弾
- 追尾：最適な対象を選び、方向を毎フレーム補正
- 探知攻撃：設置後に索敵し、対象が近づくと起動
- 持続範囲：一定時間、間隔ダメージまたは回復

### その他

- 魔力100、消費後ディレイ付き自動回復
- 魔力ゲージ、選択UI、消費魔力・ダメージ・クールダウン表示
- PC、タッチ、ゲームパッド入力
- サーバー側の入力検証、照準距離制限、視線制限、レート制限、クールダウン判定
- レイキャストによる高速弾の当たり判定
- NPCとプレイヤーの両方に対応
- 同一チームと `MagicTeam` 属性による味方判定
- クライアント側VFXとサーバー側ヒット判定の分離

## 導入方法

### 方法0：Studio Command Bar（手動配置ミスを避ける推奨方法）

1. StudioのPlayテストを停止します。
2. `View > Command Bar` を表示します。
3. `InstallRobloxMagicSystem.lua` の全内容をCommand Barへ貼り付けて実行します。
4. Outputに `[Magic Installer] 完了` と表示されたらPlayテストを開始します。

このインストーラーは、必要なFolder・ModuleScript・Script・LocalScript・Remoteを正しい名前と種類で作成または更新します。`ManaService.lua` のように拡張子付きで作られた古い重複オブジェクトも、対象フォルダ内では整理します。

### 方法A：Rojo

1. このフォルダをプロジェクトとして開きます。
2. `rojo serve` を実行します。
3. Roblox StudioのRojoプラグインから接続します。
4. Playテストを開始します。

`default.project.json` がRemoteEventとRemoteFunctionも作成します。

### 方法B：Studioへ手動配置

Explorerで次を作成し、各ファイルの内容を対応するScriptへ貼り付けます。Studio上の名前には `.lua`、`.server.lua`、`.client.lua` を付けません。

```text
ReplicatedStorage
├─ Shared (Folder)
│  ├─ SpellDefs (ModuleScript)
│  ├─ ElementDefs (ModuleScript)
│  └─ SharedUtil (ModuleScript)
└─ Remotes (Folder)
   ├─ CastSpellRequest (RemoteEvent)
   ├─ SpellFx (RemoteEvent)
   └─ GetSpellPreview (RemoteFunction)

ServerScriptService
└─ Magic (Folder)
   ├─ SpellService (Script)
   └─ Modules (Folder)
      ├─ BehaviorResolver (ModuleScript)
      ├─ ManaService (ModuleScript)
      └─ StatusService (ModuleScript)

StarterPlayer
└─ StarterPlayerScripts
   └─ SpellClient (LocalScript)
```

`SpellService` はRemotesが不足している場合に自動作成するため、手動作成を忘れても起動できます。

### Studio上の名前について

手動配置では、ModuleScript名に拡張子を付けないでください。特に次の3つは完全一致が必要です。

```text
ServerScriptService/Magic/Modules/ManaService
ServerScriptService/Magic/Modules/BehaviorResolver
ServerScriptService/Magic/Modules/StatusService
```

更新版`SpellService`と`BehaviorResolver`は、互換用として末尾`.lua`の名前も検出しますが、正式名は拡張子なしです。

## 操作

- `Q`：属性を変更
- `E`：出し方を変更
- `F`：攻撃形態を変更
- `R` または左クリック：発動
- ゲームパッド：右トリガーで発動
- タッチ：画面右下の `CAST` ボタン

## NPCの準備

NPC Modelに次を入れてください。

```text
EnemyNPC (Model)
├─ Humanoid
└─ HumanoidRootPart
```

NPCを味方として扱う場合は、Modelに文字列属性 `MagicTeam` を設定します。プレイヤー側にも同じ値を `Player` またはCharacterへ設定すると、同じ陣営として判定されます。

例：

```text
Player.MagicTeam = "Blue"
AllyNPC.MagicTeam = "Blue"
EnemyNPC.MagicTeam = "Red"
```

通常のRoblox Teamに所属し、`Neutral == false` のプレイヤー同士も味方です。

## バランス調整

- 属性値：`ReplicatedStorage/Shared/ElementDefs.lua`
- 消費魔力、ダメージ、範囲、時間、速度：`ReplicatedStorage/Shared/SpellDefs.lua`
- 最大魔力、回復速度：`SpellDefs.Mana`
- Remote制限、最大照準距離、最大同時対象数：`SpellDefs.Security`

クライアントから送られたダメージ、消費魔力、クールダウン値は使用しません。すべてサーバー側の定義から再構築します。

## 本番投入前チェック

1. Studioの `Test > Start` で2人以上のクライアントを起動し、味方判定とレプリケーションを確認します。
2. StreamingEnabledを使う場合、広いマップで空中・地面設置が期待通りか確認します。
3. NPCの移動速度を別システムから変更するゲームでは、移動速度修正を共通のModifierシステムへ統合してください。
4. 大人数サーバーでは、VFX密度と最大対象数を実機で計測して調整してください。
5. `ElementDefs` と `SpellDefs` はReplicatedStorageにあるため閲覧可能ですが、サーバーが全値を再計算・検証するので改変されたクライアント値は採用されません。

## 自動生成される実行時フォルダ

```text
Workspace
└─ MagicRuntime
   └─ Projectiles
```

クライアントごとの一時VFXは `Workspace/MagicClientFx_<UserId>` に作られ、そのクライアントにだけ存在します。
