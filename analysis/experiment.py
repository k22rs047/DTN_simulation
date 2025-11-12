import pandas as pd
import pynetlogo
import subprocess

netlogo = pynetlogo.NetLogoLink(
    gui = True,
)

#モデル読み込み
netlogo.load_model('../models/PRoPHET/trust_prophet.nlogo')

#実験用パラメーターのマッピング
para_map = {
    'comm-range' : '55',
    'num-nodes' : '100',
    'ttl-hops' : '15',
    'buffer-limit' : '20',
    'messages' : '20',
    'p-plus' : '0',
    'blackhole-rate' : '0',
    'evacuee-rate' : '50',
    'history-limit' : '5'
}

#パラメータの設定
for name, value in para_map.items():
    observer_cmd = "set " + name + " " + value
    netlogo.command(observer_cmd)

#実験に利用する値
#一回の実験でモデルを実行する回数
experiment_num = 10
ticks_limit = 100
cmd_analysis = 'python analysis_trust_prophet.py'
cmd_average = 'python analyze_results.py'

#実験の実行
def run_experiment(experiment_num):
    for i in range(experiment_num):
        netlogo.command("setup")
        netlogo.command("repeat " + str(ticks_limit) +  " [ go ]")
        subprocess.call(cmd_analysis)
    #平均を求める
    subprocess.call(cmd_average)

#対照実験用のパラメータ
v_name = 'blackhole-rate'
experiment_list = [0, 10, 20, 30, 40]

for para in experiment_list:
    netlogo.command("set " + v_name + " " + para)
    run_experiment(experiment_num)

#シミュレーターの停止
netlogo.kill_workspace()