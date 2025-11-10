extensions [table]  ;拡張機能

;大域変数
globals [
  P-INIT      ;初期予測値
  GAMMA       ;aging係数
  BETA        ;推移性係数
  arrived-count ;到達したメッセージ数
  shelter-patch ;避難所の中心
  shelter-radius;避難所の範囲
  event-log-file     ;イベントログファイル名
  decision-log-file   ;転送ログファイル
  done?              ;停止フラグ
]

;避難所のフィールド変数
patches-own [
  shelter?   ;避難所かどうか
]

;ノードのフィールド変数
turtles-own [
  node-id          ;オブジェクトの番号
  msg-cnt          ;生成したメッセージの数
  p-table          ;[dst-id -> p]  Map{key,value}(連想配列)
  trust-table      ;[node-id -> trust] Map{key,value}(連想配列)
  buffer           ;[[msg-id, src-id, dst-id, ttl], ...]
  delivered-list   ;宛先として受け取ったmsg-idのリスト
  forwarded-list   ;転送処理をした情報を保持[[msg-id, node-id], ...]
  transfer-history ;一定時間保持するリスト
  evacuee?         ;避難者かどうか
  blackhole?       ;ブラックホールノードかどうか
]

;グローバル変数の初期化
to init-globals
  set P-INIT 0.75
  set GAMMA 0.98
  set BETA 0.25
  set shelter-radius 100

  set arrived-count 0
  set event-log-file "data/prophet_event_log.csv"
  set decision-log-file "data/prophet_decision_log.csv"
  set done? false
end

;-------------初期化---------------
to setup
  clear-all
  init-globals
  setup-map
  setup-shelter
  setup-nodes
  setup-blackholes
  setup-messages
  init-log-file
  reset-ticks
end

;マップの初期化
to setup-map
  ;resize-world -350 350 -350 350
  set-patch-size 1 ;1パッチ = 1m
end

to setup-shelter
  ask patches [
    set shelter? false
  ]

  set shelter-patch one-of patches with[pxcor = 100 and pycor = 100]

  ask patches [
    if distance shelter-patch <= shelter-radius [
      set shelter? true
      set pcolor orange
    ]
  ]

  ask shelter-patch [ set pcolor white ]
end

;ノードの初期化
to setup-nodes
  create-turtles num-nodes [
    set shape "circle"
    set color blue
    set size 10
    setxy random-xcor random-ycor
    set node-id who
    set msg-cnt 0
    set p-table table:make
    table:put p-table node-id 1.0  ;自分自身への到達確率を1.0に設定
    set trust-table table:make
    set buffer []
    set delivered-list []
    set forwarded-list []
    set transfer-history []
    set evacuee? false
    set blackhole? false
    set label node-id
    set label-color white
  ]

  let num-evacuees round (num-nodes * (evacuee-rate / 100))
  ask n-of num-evacuees turtles [ set evacuee? true ]
end

;メッセージの生成（初期時）
to setup-messages
  ;ブラックホールノードではない集合
  let not-blackholes turtles with [not blackhole?]

  ask n-of messages not-blackholes [
    set msg-cnt msg-cnt + 1
    let msg-id (word node-id "-" msg-cnt)
    let src-id node-id
    let dst-id [node-id] of one-of other not-blackholes
    let ttl ttl-hops

    ask turtle dst-id [ set color yellow ]
    set buffer lput (list msg-id src-id dst-id ttl) buffer
    set color brown
  ]
end

;ブラックホールノードの設定
to setup-blackholes
  let num-blackholes round (num-nodes * (blackhole-rate / 100))

  ask n-of num-blackholes turtles [
    set blackhole? true
    set color gray
  ]
end

;ログファイル初期化
to init-log-file
  ;file-deleteが失敗する場合があるので、念のためfile-close
  file-close-all

  ;ログファイルおよびヘッダの出力
  let event-header "ticks,msg-id,src-id,dst-id,ttl,sender,receiver,sender-p,receiver-p,event"
  init-file event-log-file event-header

  let decision-header "ticks,msg-id,src-id,dst-id,ttl,sender,receiver,sender-p,receiver-p,receiver-trust,p-plus-pass?,blackhole-receiver?,transfer-outcome"
  init-file decision-log-file decision-header
end

;----------------メインループ---------------
to go
  if ticks = 1500 [stop]
  move-nodes
  update-links
  forward-messages
  cleanup-buffer
  cleanup-transfer-history
  aging
  tick
end

;リンクの更新
to update-links
  ;通信範囲外のリンクを削除
  ask links [
    if link-length > comm-range [
      ;リンクが切れるタイミングで、重複処理のリストをクリアにする
      cleanup-forwarded-list end1 end2
      die
    ]
  ]

  ;通信範囲内のリンクを作成
  ask turtles [
    let nearby other turtles in-radius comm-range
    ask nearby [
      let a myself
      let b self
      if not link-neighbor? myself [
        create-link-with myself [ set color gray ]
        ;リンクが形成されたタイミング
        ;到達確率の更新
        update-encounter a b
        update-transitivity a b
      ]
    ]
  ]
end

to forward-messages
  ;ブラックホールノードではない集合
  let not-blackholes turtles with [not blackhole?]

  ;ブラックホールノードは転送しない事を前提としている
  ;ブラックホールではないノード（送信側）をループ
  ask not-blackholes [
    let sender self

    ;送信側のbufferをループ
    foreach buffer [
      msg ->
      ;隣接ノード（受信候補）をループ
      ask link-neighbors [
        handle-message-transfer sender self msg
      ]
    ]
  ]
end

to handle-message-transfer [sender receiver msg]
  ;メッセージの要素を取り出す
  let msg-id item 0 msg
  let src-id item 1 msg
  let dst-id item 2 msg
  let ttl item 3 msg

  let send-msg replace-item 3 msg (ttl - 1)

  let sender-id [node-id] of sender
  let receiver-id [node-id] of receiver
  let sender-p (get-p ([p-table] of sender) dst-id)  ;送信者側の宛先までの到達確率
  let receiver-p (get-p ([p-table] of receiver) dst-id) ;受信者側の宛先までの到達確率
  let receiver-trust get-trust ([trust-table] of sender) ([node-id] of receiver)
  
  let ttl-ok? (ttl > 0)
  let is-not-forwarded (not member? (list msg-id receiver-id) ([forwarded-list] of sender))
  let is-not-in-buffer (empty? filter [m -> item 0 m = msg-id] ([buffer] of receiver))
  let blackhole-receiver? [blackhole?] of receiver
  let p-improved? (sender-p < receiver-p)

  if p-improved? and ttl-ok? and is-not-forwarded and is-not-in-buffer [
    ifelse receiver-id = dst-id [
      ;宛先ノードへの到達処理
      process-delivery sender receiver msg-id src-id dst-id ttl sender-p receiver-p receiver-trust blackhole-receiver?
    ] [
      ;中継ノードへの転送処理
      process-relay sender receiver send-msg msg-id src-id dst-id ttl sender-p receiver-p receiver-trust blackhole-receiver?
    ]
  ]
end

;メッセージの宛先到達処理
to process-delivery [sender receiver msg-id src-id dst-id ttl sender-p receiver-p receiver-trust blackhole-receiver?]

  if not member? msg-id ([delivered-list] of receiver) [
    let sender-id [node-id] of sender
    let receiver-id [node-id] of receiver

    ;受信側のリストに追加
    ask receiver [
      set delivered-list lput msg-id delivered-list
      set color red

      let m-count get-trust trust-table sender-id
      set m-count m-count + 1
      set-trust trust-table sender-id m-count
    ]

    set arrived-count arrived-count + 1

    log-event msg-id src-id dst-id ttl sender-id receiver-id sender-p receiver-p "ARRIVED"

    let p-plus-pass? false
    log-decision-event msg-id src-id dst-id ttl sender-id receiver-id sender-p receiver-p receiver-trust p-plus-pass? blackhole-receiver? "Delivered"

    if arrived-count >= messages [
      ;stop-simulation
    ]
    
  ]
end

;中継ノード転送処理
to process-relay [sender receiver send-msg msg-id src-id dst-id ttl sender-p receiver-p receiver-trust blackhole-receiver?]
  let sender-id [node-id] of sender
  let receiver-id [node-id] of receiver
  let p-plus-pass? ((sender-p * (1 + p-plus / 100)) < receiver-p)
  let transfer-outcome "Failed"

  if receiver-trust >= 1 [
    ifelse not blackhole-receiver? [
      
      ask receiver [
        ;bufferの末尾に追加する
        set buffer lput send-msg buffer
        set color green

        ;受信側で送信側のtrustを上げる
        let m-count get-trust trust-table sender-id
        set m-count m-count + 1
        set-trust trust-table sender-id m-count
      ]

      log-event msg-id src-id dst-id ttl sender-id receiver-id sender-p receiver-p "FORWARDED"
      set transfer-outcome "Trust_Transfer"
    ] [
      ;ブラックホールノードへの転送
      set transfer-outcome "BH_Transfer"
    ]
    
    if member? (list msg-id receiver-id) ([transfer-history] of sender) [
      ;送信側が受信側のtrustを下げる
      let trust get-trust ([trust-table] of sender) receiver-id
      set trust trust - 1
      set-trust ([trust-table] of sender) receiver-id trust
    ]

    ;送信側の転送済みリストに追加
    ask sender [
      let temp (list msg-id receiver-id)
      set forwarded-list lput temp forwarded-list
      set transfer-history lput temp transfer-history
    ]

    log-decision-event msg-id src-id dst-id ttl sender-id receiver-id sender-p receiver-p receiver-trust p-plus-pass? blackhole-receiver? transfer-outcome
  ]

  if receiver-trust = 0 [
    ifelse p-plus-pass? [
      ifelse not blackhole-receiver? [

        ask receiver [
          ;bufferの末尾に追加する
          set buffer lput send-msg buffer
          set color green

          let m-count get-trust trust-table sender-id
          set m-count m-count + 1
          set-trust trust-table sender-id m-count
        ]

        log-event msg-id src-id dst-id ttl sender-id receiver-id sender-p receiver-p "FORWARDED"
        set transfer-outcome "Low_Trust_Transfer"
      ] [
        set transfer-outcome "BH_Transfer"
      ]
      
      log-decision-event msg-id src-id dst-id ttl sender-id receiver-id sender-p receiver-p receiver-trust p-plus-pass? blackhole-receiver? transfer-outcome
    ] [
      log-decision-event msg-id src-id dst-id ttl sender-id receiver-id sender-p receiver-p receiver-trust p-plus-pass? blackhole-receiver? transfer-outcome
    ]

    if member? (list msg-id receiver-id) ([transfer-history] of sender) [
      let trust get-trust ([trust-table] of sender) receiver-id
      set trust trust - 1
      set-trust ([trust-table] of sender) receiver-id trust
    ]

    ;送信側の転送済みリストに追加
    ask sender [
      let temp (list msg-id ([node-id] of receiver))
      set forwarded-list lput temp forwarded-list
      set transfer-history lput temp transfer-history
    ]

  ]
end

to stop-simulation
  file-close-all

  ;シミュレーション停止
  set done? true
end

to init-file [file-name header]
  file-delete file-name
  file-open file-name
  file-print header
  file-close
end

to cleanup-buffer
  ask turtles [
    ;TTL=0の削除
    set buffer filter [msg -> item 3 msg > 0] buffer
    ;FIFOを適用
    while [length buffer > buffer-limit] [
      set buffer remove-item 0 buffer
    ]
  ]
end

to cleanup-transfer-history
  ask turtles [
    ;FIFOを適用
    while [length transfer-history > history-limit] [
      set transfer-history remove-item 0 transfer-history
    ]
  ]
end

;イベントログの出力
to log-event [msg-id src-id dst-id ttl sender receiver sender-p receiver-p event]
  file-open event-log-file
  file-print (word ticks "," msg-id "," src-id "," dst-id "," ttl "," sender "," receiver "," sender-p "," receiver-p "," event)
  file-close
end

to log-decision-event [msg-id src-id dst-id ttl sender receiver sender-p receiver-p receiver-trust p-plus-pass? blackhole-receiver? transfer-outcome]
  file-open decision-log-file
  file-print (word ticks "," msg-id "," src-id "," dst-id "," ttl "," sender "," receiver "," sender-p "," receiver-p "," receiver-trust "," p-plus-pass? "," blackhole-receiver? "," transfer-outcome)
  file-close
end

to cleanup-forwarded-list [a b]
  ask a [
    set forwarded-list filter [msg -> item 1 msg != [node-id] of b] forwarded-list
  ]
  ask b [
    set forwarded-list filter [msg -> item 1 msg != [node-id] of a] forwarded-list
  ]
end

to move-nodes
  ask turtles [
    ifelse evacuee? [
      ifelse [shelter?] of patch-here [
        rt random 50 - random 50

        fd 0.5 + random-float 0.5

        if not[shelter?] of patch-here [
          bk 1.0 + random-float 0.5
          face shelter-patch
          rt random 20 - random 10
        ]

      ] [
        face shelter-patch
        fd 0.5 + random-float 0.5
      ]

    ] [
      rt random 50 - random 50
      fd 1.0 + random-float 0.5  ; 1.0～1.5 m
      if xcor > max-pxcor [ rt 180 ]
      if xcor < min-pxcor [ rt 180 ]
      if ycor > max-pycor [ rt 180 ]
      if ycor < min-pycor [ rt 180 ]
    ]
  ]
end

;node-id(key)の到達確率を取得
to-report get-p [table key]
  let value table:get-or-default table key 0
  report value
end

;node-id(key)と到達確率(value)を設定
to set-p [table key value]
  table:put table key value
end

;node-id(key)の信用度を取得
to-report get-trust [table key]
  let value table:get-or-default table key 0
  report value
end

;node-id(key)と信用度(value)を設定
to set-trust [table key value]
  table:put table key value
end

;リンク形成時に適用
;P(A,B) = P(A,B)old + (1 − P(A,B)old) ∗ Pinit
to update-encounter[a b]
  ask a[
    let p-old (get-p p-table [node-id] of b)
    let p-new p-old + (1 - p-old) * P-INIT
    if p-new > 1 [ set p-new 1 ]
    set-p p-table ([node-id] of b) p-new
  ]

  ask b [
    let p-old (get-p p-table [node-id] of a)
    let p-new p-old + (1 - p-old) * P-INIT
    if p-new > 1 [ set p-new 1 ]
    set-p p-table ([node-id] of a) p-new
  ]
end

;リンクが存在しないノードのみに適用
;P(A,B) = P(A,B)old ∗ (γ＾k)
;k＝1 (1tick)
to aging
  ask turtles [
    let contacts [node-id] of link-neighbors
    let keys table:keys p-table

    foreach keys [
      key ->
      if key != node-id [
        let p-old (get-p p-table key)
        if not member? key contacts [
          let p-new p-old * GAMMA
          table:put p-table key p-new
        ]
      ]

    ]
  ]
end

;リンク形成時に適用
;P(A,C) = P(A,C)old + (1 − P(A,C)old) ∗ P(A,B) ∗ P(B,C) ∗ β
to update-transitivity [a b]
  ask a [
    let p-ab (get-p p-table [node-id] of b)
    let keys table:keys ([p-table] of b)
    foreach keys [
      key ->
      if key != node-id and key != [node-id] of b [
        let p-ac (get-p p-table key)
        let p-bc (get-p ([p-table] of b) key)
        let p-new p-ac + (1 - p-ac) * p-ab * p-bc * BETA
        if p-new > 1 [ set p-new 1 ]
        set-p p-table key p-new
      ]
    ]
  ]

  ask b [
    let p-ba (get-p p-table [node-id] of a)
    let keys table:keys ([p-table] of a)
    foreach keys [
      key ->
      if key != node-id and key != [node-id] of a [
        let p-bc (get-p p-table key)
        let p-ac (get-p ([p-table] of a) key)
        let p-new p-bc + (1 - p-bc) * p-ba * p-ac * BETA
        if p-new > 1 [ set p-new 1 ]
        set-p p-table key p-new
      ]
    ]
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
312
10
1021
720
-1
-1
1.0
1
10
1
1
1
0
0
0
1
-350
350
-350
350
0
0
1
ticks
30.0

BUTTON
69
451
133
484
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
172
451
235
484
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
57
68
229
101
num-nodes
num-nodes
10
100
100.0
1
1
NIL
HORIZONTAL

SLIDER
57
22
229
55
comm-range
comm-range
10
100
55.0
5
1
NIL
HORIZONTAL

SLIDER
59
118
231
151
ttl-hops
ttl-hops
0
100
15.0
1
1
NIL
HORIZONTAL

SLIDER
59
164
232
197
buffer-limit
buffer-limit
1
messages
20.0
1
1
NIL
HORIZONTAL

MONITOR
105
514
203
559
到達したメッセージ
arrived-count
17
1
11

SLIDER
59
212
231
245
messages
messages
1
num-nodes
20.0
1
1
NIL
HORIZONTAL

SLIDER
61
257
233
290
p-plus
p-plus
0
100
30.0
5
1
%
HORIZONTAL

SLIDER
63
305
235
338
blackhole-rate
blackhole-rate
0
70
20.0
5
1
%
HORIZONTAL

SLIDER
64
348
236
381
evacuee-rate
evacuee-rate
0
100
50.0
5
1
%
HORIZONTAL

SLIDER
64
392
236
425
history-limit
history-limit
0
100
4.0
1
1
NIL
HORIZONTAL

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.4.0
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
