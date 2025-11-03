import pandas as pd
import os

#csv読み込み
df = pd.read_csv("../models/PRoPHET/data/prophet_decision_log.csv")

#メッセージの総数（=初期に生成した数）
#total_messages = df['msg-id'].unique()
#全メッセージ数を記述
total_messages = 17
#宛先に到着したメッセージを取得
delivered_count = df[df['transfer-outcome'] == 'Delivered']['msg-id'].unique()

#配信率の計算
delivery_ratio = len(delivered_count) / total_messages
print("配信率：" + str(delivery_ratio))

#メッセージの転送
successful_transfers = ['Delivered', 'Low_Trust_Transfer', 'BH_Transfer', 'Trust_Transfer']

#転送したメッセージの数
total_transfers = df[df['transfer-outcome'].isin(successful_transfers)].shape[0]
print("総転送回数：" + str(total_transfers))


#提案手法の閾値によって転送しなかった回数
failed_transfers = df[(df['transfer-outcome'] == 'Failed') & (df['p-plus-pass?'] == False)].shape[0]
#すべての転送機会
total_transfer_opportunities = df.shape[0]
#抑制率
failed_ratio = failed_transfers / total_transfer_opportunities

print("提案手法により転送を拒否した回数：" + str(failed_transfers))
print("すべての転送機会：" + str(total_transfer_opportunities))
print("抑制率：" + str(failed_ratio))

#遅延率の計算
#初期生成なので0ticks
creation_times = 0
delivery_rows = df[df['transfer-outcome'] == 'Delivered']
delivery_rows_length = len(delivery_rows)

## 配信完了メッセージIDごとに、最も早い配信完了時刻を取得
#delivery_times = delivery_rows.groupby('msg-id')['ticks'].min().rename('delivery_time')
ticks_values = delivery_rows['ticks']
sum_ticks_values = ticks_values.sum()

avarage_latency = sum_ticks_values / delivery_rows_length

print("平均遅延時間：" + str(avarage_latency) + " [ticks]")
print("--------------------------------------------------")

output_path = './data/analysis_log.csv'

data = {
    'delivery_ratio': [delivery_ratio],
    'total_transfers': [total_transfers],
    'failed_transfers': [failed_transfers],
    'total_transfer_opportunities': [total_transfer_opportunities],
    'failed_ratio': [failed_ratio],
    'avarage_latency_ticks': [avarage_latency]
}

df2 = pd.DataFrame(data)

file_exists = os.path.exists(output_path)
file_is_empty = False

if file_exists:
    if os.path.getsize(output_path) == 0:
        file_is_empty = True

if file_exists:
    if file_is_empty:
        df2.to_csv(output_path, mode='w', header=True, index=False)
    else:
        df2.to_csv(output_path, mode='a', header=False, index=False)