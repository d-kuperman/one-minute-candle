// A SCRIPT: production event handlers are renamed, so no orders can be sent.
#define OnInit ProductionInit
#define OnTick ProductionTick
#define OnTrade ProductionTrade
#define OnTradeTransaction ProductionTransaction
#define OnTester ProductionTester
#define OnDeinit ProductionDeinit
#include "../CandleMomentum_Research_v1_2.mq5"
#undef OnInit
#undef OnTick
#undef OnTrade
#undef OnTradeTransaction
#undef OnTester
#undef OnDeinit

int failures=0,assertions=0;
void Check(bool ok,string name) { assertions++; if(!ok) failures++; Print(ok?"PASS ":"FAIL ",name); }
bool Near(double a,double b) { return MathAbs(a-b)<1e-8; }
void OnStart() {
 tf=PERIOD_M1; tick_size=0.00001; point_size=0.00001; digits=5;
 MqlRates v={}; v.time=60; v.open=1.10002; v.high=1.10020; v.low=1.10000; v.close=1.10018;
 MqlTick q={}; q.time=120; q.time_msc=120000; q.bid=1.10018; q.ask=1.10020;
 Signal s;
 Check(MakeSignal(v,q,120,0.0002,true,s),"bull candle accepted");
 Check(s.side==1 && Near(s.body_pct,80) && s.body_ok,"BUY 80% inclusive");
 Check(s.pips_ok && Near(s.range_pips,2),"range exactly 2 pips");
 Check(s.atr_ok && Near(s.range_atr,1),"RangeATR exactly 1");
 Check(Near(s.sl,v.low) && Near(s.tp,1.10040),"BUY SL and RR 1");
 v.open=1.10018; v.close=1.10002;
 MakeSignal(v,q,120,0.0002,true,s);
 Check(s.side==-1 && s.body_ok && Near(s.sl,v.high),"SELL 80% and SL");
 Check(Near(s.tp,1.10016),"SELL TP from Bid");
 v.close=1.10004; MakeSignal(v,q,120,0.0002,true,s); Check(!s.body_ok,"body below threshold");
 v.open=1.10018; v.close=1.10002; v.high=1.100199;
 MakeSignal(v,q,120,0.0002,true,s); Check(!s.pips_ok,"range slightly below threshold");
 v.high=1.10020; MakeSignal(v,q,120,0,false,s);
 Check(!s.atr_valid && !s.atr_ok && s.combined,"missing ATR does not block pips-only mode");
 MakeSignal(v,q,120,EMPTY_VALUE,true,s); Check(!s.atr_valid,"invalid ATR excluded");
 v.time=120; Check(!MakeSignal(v,q,120,0.001,true,s),"future candle rejected"); v.time=60;
 v.close=v.open; Check(!MakeSignal(v,q,120,0.001,true,s),"doji excluded");
 v.high=v.low; Check(!MakeSignal(v,q,120,0.001,true,s),"zero range excluded");
 Check(Near(FloorVolume(0.019,0.01),0.01),"lot rounds down");
 Check(Near(FloorVolume(0.009,0.01),0),"below minimum never raised");
 Check(Near(RoundTick(1.123456),1.12346),"five-digit tick grid");
 tick_size=0.0001; digits=4; Check(Near(RoundTick(1.123456),1.1235),"four-digit tick grid");
 tick_size=0.00001; digits=5;
 Excursion e; ZeroMemory(e); Observe(e,1,1.1,1.1002,1000); Observe(e,1,1.1,1.0999,2000);
 Check(Near(e.mfe,0.0002) && Near(e.mae,0.0001) && e.mfe_time==1000 && e.mae_time==2000,"BUY MFE MAE and times");
 ZeroMemory(e); Observe(e,-1,1.1,1.0998,1000); Observe(e,-1,1.1,1.1001,2000);
 Check(Near(e.mfe,0.0002) && Near(e.mae,0.0001),"SELL executable excursions");
 ZeroMemory(s); s.id="test"; s.side=1; s.entry=1.1; s.sl=1.0999; s.r=0.0001; s.path_valid=true;
 StartObservation(s); q.bid=1.10035; q.ask=1.10037; q.time_msc=3000; ResearchTick(q);
 Check(active[0].state[0]==1 && active[0].state[4]==1 && active[0].state[5]==0,"gap reaches several targets in one tick");
 Check(active[0].arrival[0]==3000 && active[0].arrival[4]==3000,"first arrival same timestamp for crossed levels");
 q.bid=1.1001; q.time_msc=4000; ResearchTick(q); Check(active[0].arrival[0]==3000,"first arrival immutable");
 q.bid=1.0998; q.time_msc=5000; ResearchTick(q); Check(ArraySize(active)==0,"stop terminates observation with gap");
 Check(groups[0].hits[4]==1 && groups[0].stops[5]==1,"target/stop mutually exclusive");
 Check(Near(groups[0].mfes[0],3.5) && Near(groups[0].maes[0],2),"MFE beyond configured TP and MAE gap");
 Observation o; ZeroMemory(o); o.s=s; o.state[0]=1; o.arrival[0]=1000;
 FinishObservation(o,"CENSORED_HORIZON",6000);
 Check(groups[0].unresolved[1]==1 && groups[0].stops[1]==0,"censored not counted as loss");
 Check(groups[0].hits[0]==2 && groups[0].unresolved[0]==0,"target remains resolved at horizon");
 double med[4]={4,1,3,2}; Check(Near(Median(med),2.5),"exact even median");
 Check(BodyBin(80)=="[80,90)" && BodyBin(100)=="[95,100]","non-overlapping body bins");
 q.bid=1.1; q.ask=1.099; Check(!GoodQuote(q),"crossed quote excluded");
 Print("CMR_UNIT_RESULT assertions=",assertions," failures=",failures);
 int report=FileOpen("CMR_UnitTests.txt",FILE_WRITE|FILE_TXT|FILE_ANSI);
 if(report!=INVALID_HANDLE) { FileWrite(report,"assertions=",assertions," failures=",failures); FileClose(report); }
}
