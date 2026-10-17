from pathlib import Path
import re,json
p=Path('EMA200_MeanReversion_M1_V1.mq5')
s=p.read_text(encoding='utf-8-sig')
checks={
 'native_MQL5_indicator_handle': 'ema_handle=iMA(_Symbol,PERIOD_M15,EMA_Period,0,MODE_EMA,PRICE_CLOSE)' in s,
 'closed_M1_only': 'CopyRates(_Symbol,PERIOD_M1,1,1,bars)' in s,
 'EMA_closed_time_guard': 'mt+900>boundary' in s,
 'consume_bar_before_signal': s.index('last_bar=bar; // Consumir')<s.index('if(Signal(bar))'),
 'market_orders_only': 'TRADE_ACTION_PENDING' not in s,
 'no_manual_closes': all(x not in s for x in ['PositionClose(', 'PositionClosePartial(', 'TRADE_ACTION_CLOSE_BY']),
 'no_take_profit': all(x.strip()=='0' for x in re.findall(r'req\.tp\s*=\s*([^;]+);',s)),
 'all_sends_check_retcode': s.count('OrderSend(req,res)')==2 and 'sent && res.retcode==TRADE_RETCODE_DONE' in s and 'res.retcode!=TRADE_RETCODE_DONE_PARTIAL' in s,
 'risk_from_original_deal_SL': 'HistoryDealGetDouble(d,DEAL_SL)' in s and 'st.r=MathAbs(entry-sl)' in s,
 'profit_and_margin_native': 'OrderCalcProfit(' in s and 'OrderCalcMargin(' in s,
 'volume_down_and_budget_recheck': 'MathFloor(MathMin(maxvol,budget/perlot)/step)' in s and 'volume*perlot>budget' in s,
 'no_compounding': 'budget=base_balance*RiskPercent/100.0' in s,
 'persistent_live_state': 'FileWriteStruct(f,st)' in s and 'FileReadStruct(f,st)' in s,
 'tester_state_isolation': 'if(testing || !FileIsExist(state_file)) return false' in s,
 'trailing_before_new_bar_gate': s.index('   Manage(q);\n   datetime bar=')<s.index('if(bar<=0 || bar==last_bar)'),
 'spread_only_on_entry': 'UseSpreadFilter' not in s[s.index('void Manage('):s.index('bool Signal(')],
 'initial_SL_extreme': 'st.initial_sl=side==1?st.l:st.h' in s,
 'persistent_trailing_distances': 'double entry,r,volume,risk,best,worst,activation,trail_distance,activation_distance;' in s,
}
print(json.dumps(checks,indent=2))
assert all(checks.values())
Path('validacion_estatica.json').write_text(json.dumps({'scope':'Inspeccion estructural del fuente; no ejecuta MQL5 ni un backtest','checks':checks},indent=2),encoding='utf-8')
