# Lobby Magic V2

ロビーの魔法工房で名前と性能を決め、最大5個まで保存して戦うRoblox向け魔法システムです。

## 主な機能

- 魔法名を1〜20文字で設定
- 魔法を最大5個まで所持
- 戦闘中はホットバー、PCの1〜5キーで装備変更
- 魔法名・全設定・装備中スロットをDataStoreへ保存
- ForgeUIZone内の工房UIで魔法を作成・削除
- 球数、球サイズ、球速、着弾方法を組み合わせて魔法を作成
- クライアントは選択内容だけを送り、マナ・ダメージ・CDはサーバーで再計算

## 現在の設定

### 球数

| 選択 | 発射角度 | 1球の威力倍率 | 魔力 | CD |
|---|---|---:|---:|---:|
| 1球 | 0° | ×1.00 | +0 | +0秒 |
| 2球 | -4°, +4° | ×0.62 | +5 | +0.35秒 |
| 3球 | -7°, 0°, +7° | ×0.48 | +9 | +0.65秒 |
| 5球 | -12°, -6°, 0°, +6°, +12° | ×0.32 | +15 | +1.1秒 |

### 球サイズ

| 選択 | 威力倍率 | 速度倍率 | 見た目倍率 | 魔力 | CD |
|---|---:|---:|---:|---:|---:|
| 小 | ×0.80 | ×1.15 | ×0.75 | -3 | -0.2秒 |
| 普通 | ×1.00 | ×1.00 | ×1.00 | +0 | +0秒 |
| 大 | ×1.25 | ×0.80 | ×1.30 | +7 | +0.5秒 |

### 球速

| 選択 | 基本速度 | 最大射程 | 魔力 | CD |
|---|---:|---:|---:|---:|
| 遅い | 70 stud/秒 | 120 stud | -2 | +0秒 |
| 普通 | 92 stud/秒 | 145 stud | +0 | +0秒 |
| 速い | 130 stud/秒 | 160 stud | +4 | +0.2秒 |

### 着弾方法

| 選択 | 爆発半径 | 威力倍率 | 魔力 | CD |
|---|---:|---:|---:|---:|
| 直撃 | 0 | ×1.20 | +7 | +0.8秒 |
| 小爆発 | 6 stud | ×1.05 | +10 | +1.1秒 |
| 通常爆発 | 12 stud | ×1.00 | +14 | +1.4秒 |
| 大爆発 | 18 stud | ×0.85 | +22 | +1.8秒 |

属性・生成方法・対象・発生場所は現在、火・生成・敵・自分の1種類です。

### 魔力と威力

標準構成は1球・普通サイズ・普通速度・通常爆発です。

- 魔力37
- CD 3.5秒
- 1球25ダメージ
- 爆発半径12 stud

最大構成の5球・大・速い・大爆発でも魔力71です。魔力80を超える組み合わせはカタログで無効になります。球数を増やすと1球の威力を下げるため、球数倍のダメージにはなりません。

## 保存とスロット

保存先はLobbyMagicV2_Spells_v1です。プレイヤーごとに次を保存します。

- データ形式のバージョン
- 装備中スロット
- 最大5件の「名前 + 全設定」

作成・削除後は約1秒で保存し、さらに60秒ごと・退出時・サーバー終了時にも保存します。読み込みに失敗した本番サーバーでは、古いデータを上書きしないよう作成と削除を停止します。

StudioでDataStoreを確認する場合は、Experienceを公開したうえで、Game SettingsのSecurityからEnable Studio Access to API Servicesを有効にしてください。無効なStudioでは、そのPlayテスト中だけの一時データに切り替わります。

## 操作

### 魔法工房

1. ForgeUIZoneへ入る
2. 魔法名を入力
3. 8項目を選択
4. 「新しい魔法として保存」を押す
5. 上部の1〜5スロットを押すと装備変更
6. スロットを選んで「削除」を押すと、その魔法を削除

### 戦闘

- PC：1〜5で魔法変更、左クリックまたはFで発動
- ゲームパッド：画面ホットバーで変更、R2で発動
- タッチ：画面ホットバーで変更、狙う場所をタップしてFIRE

装備変更でクールダウンは解除されないため、切替による連射はできません。

## Studioで作成する3D構造

Workspaceへ次の構造を完全一致の名前で作成します。5個の中身はすべてBasePartです。

~~~text
Workspace
└─ LMV2_World (Folder または Model)
   ├─ LobbySpawn
   ├─ GroundSpawn
   ├─ ForgeUIZone
   ├─ ExitGate
   └─ ReturnGate
~~~

| 名前 | 役割 | 推奨設定 |
|---|---|---|
| LobbySpawn | 参加・敗北・帰還位置 | Anchored=true |
| GroundSpawn | 出撃位置 | Anchored=true |
| ForgeUIZone | 工房UIの表示・編集範囲 | Anchored=true、CanCollide=false、Transparency=1 |
| ExitGate | グラウンドへ出る | 近づける位置へ配置 |
| ReturnGate | ロビーへ戻る | グラウンド側へ配置 |

サーバーは次のPromptだけを自動追加します。

~~~text
ExitGate/LMV2_ExitPrompt
ReturnGate/LMV2_ReturnPrompt
~~~

## 炎VFXの準備

RobloxMagicSystem/InstallRobloxMagicSystem.luaで次のテンプレートを作成します。

~~~text
ReplicatedStorage
└─ FireballVFX
   └─ Templates
      ├─ Projectile
      ├─ Cast
      └─ Explosion
~~~

旧FireballServerとFireballClientは無効化し、FireballVFX/Templatesは残してください。球サイズと着弾方法に応じて、Projectile・Cast・Explosionの見た目サイズも変化します。

## Rojo

~~~bash
rojo serve LobbyMagicV2/default.project.json
~~~

旧RobloxMagicSystem/default.project.jsonと同時に同期する必要はありません。

## Remote

| Remote | 方向 | 内容 |
|---|---|---|
| LobbyActionRequest | Client → Server | CreateSpell、DeleteSpell、EquipSpell、EnterGround、ReturnLobby |
| CastSpellRequest | Client → Server | AimPosition |
| VFXEvent | Server → Client | Cast・Explosionの位置と表示倍率 |
| StateChanged | Server → Client | スロット一覧、装備中魔法、状態、マナ |
| Feedback | Server → Client | 成功・拒否・保存エラー |
| GetSnapshot | Client → Server | 初回表示用Snapshot |

クライアントからダメージ、マナ、球数、速度、爆発半径は送りません。サーバーは選択IDから最終値を構築します。

## テスト手順

1. DataStore設定を確認してPlay開始
2. 保存済み魔法が5スロットへ復元される
3. ForgeUIZone外では工房UIが非表示
4. 名前なし、21文字以上の名前が拒否される
5. 1・2・3・5球が表の角度で発射される
6. 6個目の魔法が拒否される
7. 工房内で選択中の魔法を削除できる
8. 出撃後、ホットバーと1〜5で装備変更できる
9. 装備変更しても現在のクールダウンが残る
10. 再参加後も名前・設定・装備スロットが復元される
11. 同じチームと自分自身にはダメージが入らない
12. マナ不足・CD中・不正な設定はサーバーに拒否される
