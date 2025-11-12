import pandas as pd
import os

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

#データの平均をresults_log.csvファイルに出力
data = {}
for name, value in average_values.items():
    rounded_value = sig_digits(value, sig_digits_num)

    formatted_str = f'{rounded_value:.10f}'.rstrip('0').rstrip('.')

    data[name] = [formatted_str]
    print(str(name_mapping[name]) + ": " + str(formatted_str))

output_path = './data/results_log.csv'

df = pd.DataFrame(data)

file_exists = os.path.exists(output_path)
file_is_empty = False

if file_exists:
    if os.path.getsize(output_path) == 0:
        file_is_empty = True

if file_exists:
    if file_is_empty:
        #上書き
        df.to_csv(output_path, mode='w', header=True, index=False)
    else:
        #追記
        df.to_csv(output_path, mode='a', header=False, index=False)

print("---------------------------------------")