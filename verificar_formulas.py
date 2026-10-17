# Ejecuta expresiones extraidas del fuente; no sustituye al motor MT5.
from pathlib import Path
from types import SimpleNamespace as NS
import re, math, json
s=Path('EMA200_MeanReversion_M1_V1.mq5').read_text(encoding='utf-8-sig')
start=s.index('if(range-MinCandleRangePips')+3
end=s.index(') return false;',start)
reject=s[start:end].replace('||',' or ').replace('&&',' and ')
buy=re.search(r'if\((bars\[0\]\.close>.*?)\) side=1;',s).group(1).replace('&&',' and ')
sell=re.search(r'if\((bars\[0\]\.close<.*?)\) side=-1;',s).group(1).replace('&&',' and ')
def signal(o,h,l,c,ema_value,tick):
    env=dict(range=h-l,body=abs(c-o),MinCandleRangePips=2.0,MaxCandleRangePips=0.0,
             MinBodyPercent=80.0,pip=.0001,eps=tick*1e-7,
             bars=[NS(open=o,high=h,low=l,close=c)],ema=[ema_value])
    if h<=l or eval('('+reject+')',{'__builtins__':{}},env): return 0
    if eval(buy,{'__builtins__':{}},env): return 1
    if eval(sell,{'__builtins__':{}},env): return -1
    return 0
checks={}
for tick in [.00001,.0001]:
    k=str(tick)
    checks[k+'_body_80_buy']=signal(1.1000,1.1005,1.1000,1.1004,1.1010,tick)==1
    checks[k+'_body_80_sell']=signal(1.1004,1.1005,1.1000,1.1000,1.0990,tick)==-1
    checks[k+'_exact_2_pips_rejected']=signal(1.1000,1.1002,1.1000,1.1002,1.1010,tick)==0
    checks[k+'_above_2_accepted']=signal(1.1000,1.1003,1.1000,1.1003,1.1010,tick)==1
    checks[k+'_wick_rejected']=signal(1.1000,1.1005,1.1000,1.1003,1.1010,tick)==0
    checks[k+'_ema_equal_rejected']=signal(1.1000,1.1005,1.1000,1.1004,1.1004,tick)==0
    checks[k+'_wrong_direction_rejected']=signal(1.1000,1.1005,1.1000,1.1004,1.0990,tick)==0
raw=re.search(r'double raw=([^;]+);',s).group(1)
for side in [1,-1]:
    st=NS(entry=1.1,r=.0002,side=side,trail_distance=.0002)
    stop=st.entry-side*st.r
    results=[]
    for movement in [0.0001,0.0002,0.0003,0.0005,0.0004]:
        if movement>=st.r:
            st.best=st.entry+side*max(movement, max(results,default=0))
            proposal=eval(raw,{'__builtins__':{}},{'st':st})
            stop=max(stop,proposal) if side==1 else min(stop,proposal)
        results.append(movement)
    checks[f'trailing_example_{side}']=math.isclose(stop,st.entry+side*.0003,abs_tol=1e-12)
assert all(checks.values()),checks
Path('validacion_formulas.json').write_text(json.dumps({'scope':'Expresiones de senal y distancia extraidas del .mq5, evaluadas en Python; no es ejecucion MQL5 ni backtest','checks':checks},indent=2),encoding='utf-8')
print(f'{len(checks)} comprobaciones de formulas OK')


