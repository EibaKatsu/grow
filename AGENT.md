# AGENT.md — Garmin Connect IQ「デイリー歩数モンスター」（Forerunner 255）

## 目的
Garmin Forerunner 255向けの Connect IQ **Device App（Watch App）**を作る。  
**今日の歩数だけ**を元に「小さな怪物」が**毎日育つ**。成長の暴走を防ぐため、歩数から換算した“分”は **1日60分を上限**とする。  
ユーザーは毎日アプリを開いて（またはGlanceから遷移して）「エサやり（反映）」を1回行い、成長を実感できる。

## 対象プラットフォーム
- Garmin **Connect IQ**（Monkey C）
- 対象デバイス：**Forerunner 255,260,570,他**
- アプリ種別：**Device App（Watch App）**
- Glance：**実装する**（一覧で当日の進捗を即確認）
- スマホ連携・通信なし（Webリクエストなし）

---

## コンセプト
- **今日の歩数** → **今日の分（上限60）** → **今日のXP**
- **1日1回**だけ「エサやり」でXPを反映
- レベルが上がると怪物の見た目（ステージ）が変化
- 今日の進捗（何分/60）と、次レベルまでの残りXPがすぐ分かる

---

## 入力（取得する値）
### 必須
- **今日の歩数**（ActivityMonitor）

### 使わない
- 距離、心拍、GPS、アクティビティの時間、睡眠、ストレス等は使わない  
- **歩数のみ**で完結させる

---

## スコアリング仕様
### 歩数→分 換算
- `minutes_today_raw = floor(steps_today / 100)`
- `minutes_today = min(60, minutes_today_raw)`  // 1日上限60分

### XP
- `xp_gain_today = minutes_today`  // 1分=1XP

### 1日1回の反映ルール
- 同じ日付に対して、XPを反映できるのは **1回だけ**
- 同日に何度アプリを開いても、2回目以降は加算しない

---

## 成長（レベル）仕様
### 状態（保存）
- `level`：初期値 1
- `xp_in_level`：初期値 0（現レベル内の経験値）

### 次レベル必要XP
- `need_xp(level) = 30 + level * 5`

### レベルアップ
`xp_in_level += xp_gain_today` した後に、以下を繰り返す：
- `while xp_in_level >= need_xp(level):`
  - `xp_in_level -= need_xp(level)`
  - `level += 1`

### 見た目（ステージ）
- ステージ1：Lv 1–4
- ステージ2：Lv 5–9
- ステージ3：Lv 10–14
- ステージ4：Lv 15–19
- ステージ5：Lv 20+

---

## 日付管理（重要）
### 永続保存するフィールド
`Application.Storage` などで保存：
- `level`（int）
- `xp_in_level`（int）
- `last_applied_date`（YYYYMMDD：intまたはstring）  // 最後に「エサやり（反映）」した日
- `last_seen_date`（YYYYMMDD：任意）  // UI用（省略可）
- `last_steps_applied`（int：任意）  // 「今日はXX分反映した」表示用（省略可）

### 日付の作り方
- `Toybox.Time` からローカル日付を取得し、`YYYYMMDD` 形式に変換する（int推奨）

### 日付が変わったとき
- `today != last_applied_date` なら、その日は「エサやり」可能
- レベルやXPはリセットしない（育成は継続）

---

## UI / UX 仕様
### メイン画面（1画面で完結）
表示する要素：
- 怪物スプライト（ステージ＋気分で表情差分）
- `今日: {minutes_today}/60 min`
- `Lv {level}`
- `次まで: {need_xp(level) - xp_in_level} XP`

### Glance（一覧表示）
表示する要素：
- 怪物アイコン（ステージ）
- `今日: {minutes_today}/60`
- `Lv {level}`

操作：
- Glance選択でメイン画面へ遷移

### 気分（演出のみ）
`minutes_today` により決定（反映済みかどうかとは独立）：
- 0分：しょんぼり
- 1–20分：ふつう
- 21–40分：ごきげん
- 41–60分：ハイテンション

※気分はスプライト差分（顔）または小アイコンで表現。

### 操作
- **START**：エサやり（今日のXPを反映）
  - 反映済みなら「今日はもうエサやり済み」表示
- **DOWN**：なでる（演出のみ、状態は変えない）
- **BACK**：終了

### エサやり時のフィードバック
- 「+{xp_gain_today} XP」表示
- レベルアップが起きたら「Level Up! Lv {level}」表示
- 状態は必ず保存する（反映後・レベルアップ後）

---

## データ整合性要件
- 同一日付でXPを2回反映しない
- `minutes_today` は必ず 0〜60
- 歩数が取得できない/NULLの場合は 0として扱う
- 状態更新があった場合のみ保存（無駄な書き込みを避ける）

---

## 非ゴール
- 位置共有、マルチプレイ
- Garmin Connect（スマホアプリ）側ホーム画面連携
- ネットワーク通信
- アクティビティ記録（FIT recording）
- 心拍やGPSを使った高度な推定

---

## 実装メモ（Connect IQ）
### 利用想定API
- 歩数：`Toybox.ActivityMonitor`（Info）
- ストレージ：`Toybox.Application.Storage`
- 日付：`Toybox.Time`
- UI：`Toybox.WatchUi` / `Toybox.Graphics`
- Glance：`Toybox.WatchUi`（Glance関連クラス）

### 推奨構成（例）
- `source/App.mc`：エントリ
- `source/DeviceAppView.mc`：メイン画面の表示と入力処理
- `source/GlanceView.mc`：Glance表示
- `source/Model.mc`：状態・成長ロジック（純粋関数寄り）
- `source/DateUtil.mc`：YYYYMMDD変換
- `resources/drawables/`：スプライト

### スプライト戦略（軽量）
最小：
- ステージ 5枚（Stage1〜Stage5）
- 気分 4種（sad/neutral/happy/hyped）
表現方法：
- 5×4=20枚を用意するか、
- ステージのベース絵＋顔オーバーレイで合成して枚数を減らす

---

## 受け入れ条件（Acceptance Criteria）
1. Forerunner 255でDevice Appとしてインストール・起動できる
2. Glanceに「今日の分 / Lv」が表示され、選択でメイン画面へ遷移できる
3. メイン画面に以下が表示される：
   - 怪物スプライト
   - 今日の分（steps/100、上限60）
   - レベル
   - 次レベルまでの残りXP
4. STARTで「エサやり」すると、当日分XPが **1回だけ**反映される
5. 同日に2回目のSTARTは加算されず、メッセージが出る
6. 日付が変わると翌日は再びエサやり可能になる
7. 1回のエサやりで複数レベルアップが発生しても正しく処理できる
8. 歩数が取得できない場合でもクラッシュせず0扱いで動く

---

## 手動テスト項目
- Glanceに `今日: X/60` と `Lv` が出ること、選択でメイン画面へ遷移すること
- steps=0 → minutes=0、反映しても変化なし
- steps=100 → minutes=1、+1XP、同日2回目はブロック
- steps=6000 → minutes=60（上限到達）、+60XP
- steps=20000 → minutesは60のまま
- 日付変更（端末日付変更 or DateUtilモック） → 翌日反映可能

---

## 将来拡張（MVP外）
- 設定：
  - `steps_per_min`（80/100/120）
  - `daily_cap`（30/60/90）
- 週次ミッション、コスメ解放（帽子など）
- データフィールド追加（アクティビティ中に「今日の分/60」表示 ※歩数ベース）

---

## コーディング方針
- ロジックはテストしやすく分離：
  - `calcMinutes(steps)`
  - `needXp(level)`
  - `applyXp(state, xp_gain, today)`
- API取得値は必ずnullガード
- 状態が変わったときのみStorageに保存

---

## 開発進行方針
- まずはConnect IQ開発環境を構築し、Forerunner 255向けにビルド・起動できる状態を最優先で作る
- その後は機能を一度に作り込まず、最小単位で実装して都度動作確認する
- 追加順は「起動確認 → 歩数表示 → XP反映 → 日次1回制御 → レベルアップ → Glance連携」を基本とする
- 各段階で手動テスト項目を更新し、通過を確認してから次の機能へ進む
