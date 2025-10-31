import pandas as pd
import matplotlib.pyplot as plt

#csv読み込み
df = pd.read_csv("../models/PRoPHET/data/prophet_decision_log.csv")

#メッセージの総数（=初期に生成した数）
#total_messages = df['msg-id'].unique()
total_messages = 17
#宛先に到着したメッセージを取得
delivered_count = df[df['transfer-outcome'] == 'Delivered']['msg-id'].unique()

#配信率の計算
delivery_ratio = len(delivered_count) / total_messages
print("配信率：" + str(delivery_ratio))

#メッセージの転送
successful_transfers = ['Delivered', 'Low_Trust_Transfer', 'BH_Transfer']

#転送したメッセージの数
total_transfers = df[df['transfer-outcome'].isin(successful_transfers)].shape[0]
print("総転送回数：" + str(total_transfers))


#提案手法の閾値によって転送しなかった回数
failed_transfers = df[(df['transfer-outcome'] == 'Failed') & (df['trust-tresh-pass?'] == False)].shape[0]
#すべての転送機会
total_transfer_opportunities = df.shape[0]
#抑制率
failed_ratio = failed_transfers / total_transfer_opportunities

print("閾値により転送を拒否した回数：" + str(failed_transfers))
print("すべての転送機会：" + str(total_transfer_opportunities))
print("抑制率：" + str(failed_ratio))

