import pandas as pd

#csv読み込み
df = pd.read_csv("../models/PRoPHET/data/prophet_decision_log.csv")

message_ids = df['msg-id'].unique()
delivered_count = 0


for msg_id in message_ids:
    msg_df = df[df['msg-id'] == msg_id]

    if not msg_df[msg_df['event'] == 'ARRIVED'].empty:
        delivered_count += 1


delivery_ratio = delivered_count / len(message_ids)


print("=== PROPHET 配信率 ===")
print("メッセージ総数:" + str(len(message_ids)))
print("配信済みメッセージ数:" + str(delivered_count))
print("配信率:" + str(delivery_ratio))
