import pandas as pd

read_path = './data/analysis_log.csv'
df = pd.read_csv(read_path)

average_values = df.mean()

name_mapping = {
    'delivery_ratio': '配信率',
    'total_transfers': '総転送回数',
    'failed_transfers': '閾値により転送を拒否した回数',
    'total_transfer_opportunities': 'すべての転送機会',
    'failed_ratio': '抑制率',
    'avarage_latency_ticks': '平均遅延時間[ticks]'
}

print("各実験の平均を求める:")
print("実験回数" + str(len(df)) + "回:")
print(average_values.rename(name_mapping))
print("---------------------------------------")