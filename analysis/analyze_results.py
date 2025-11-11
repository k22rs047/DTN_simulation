import pandas as pd
import numpy as np

read_path = './data/analysis_log.csv'
df = pd.read_csv(read_path)

average_values = df.mean()

name_mapping = {
    'delivery_ratio': '配信率',
    'total_transfers': '総転送回数',
    'failed_transfers': '転送を拒否した回数',
    'total_transfer_opportunities': 'すべての転送機会',
    'failed_ratio': '抑制率',
    'avarage_latency_ticks': '平均遅延時間[ticks]'
}

print("各実験の平均を求める:")
print("実験回数" + str(len(df)) + "回:")
#print(average_values.rename(name_mapping))

def sig_digits(x, n):
    #xの桁数を取得する
    import math
    if x==0:
      return 0
    else:
      digits=math.floor(math.log10(abs(x)))+1
      #n桁に丸める
      return round(x, -digits+n)

sig_digits_num = 3
formatted_dict = {}
for name, value in average_values.rename(name_mapping).items():

    rounded_value = sig_digits(value, sig_digits_num)

    formatted_str = f'{rounded_value:.10f}'.rstrip('0').rstrip('.')

    print(name, formatted_str)

print("---------------------------------------")