// EMA200 Mean Reversion M1 V1.0 -- reglas auditables, sin TP ni cierres manuales.
#property strict
#property version "1.00"
input int EMA_Period=200;
input double MinBodyPercent=80.0;
input double MinCandleRangePips=2.0;
input double MaxCandleRangePips=0.0;
input double RiskPercent=1.0;
input double FixedInitialBalance=0.0;
input bool UseSpreadFilter=true;
input double MaxSpreadPips=1.0;
input double TrailingActivationRR=1.0;
input double TrailingDistanceRR=1.0;
input int MaxOpenPositions=1; // El limite absoluto V1 sigue siendo una posicion.
input ulong MagicNumber=2001501001;
input uint MaxSlippagePoints=10;
input bool EnableDebugLogs=false;
input bool ExportTradesCSV=false;

struct TradeState
{
   int version;
   ulong id;
   datetime signal_time,opened;
   int side;
   double ema,o,h,l,c,body,range,spread,requested,initial_sl;
   double entry,r,volume,risk,best,worst,activation,trail_distance,activation_distance;
   int active,moved,recovered;
};
TradeState st;
int ema_handle=INVALID_HANDLE,csv=INVALID_HANDLE,instance_lock=INVALID_HANDLE;
double pip,point,tick_size,base_balance;
int digits;
bool testing,pending=false;
ulong pending_order=0,last_closed_id=0;
datetime last_bar=0;
string state_file,base_key;
bool trailing_block_logged=false;

string U(ulong n) { return StringFormat("%I64u",n); }
void Log(string s) { Print("EMR V1 | ",s); }
void Event(string event,string reason,double net=0,double grosspips=0,double commission=0,
           double swap=0,double fee=0,datetime closed=0,double exitprice=0)
{
   if(csv==INVALID_HANDLE) return;
   FileWrite(csv,event,reason,U(st.id),TimeToString(st.signal_time,TIME_DATE|TIME_SECONDS),
      TimeToString(st.opened,TIME_DATE|TIME_SECONDS),closed==0?"":TimeToString(closed,TIME_DATE|TIME_SECONDS),
      st.side==1?"BUY":"SELL",st.ema,(st.c-st.ema)/pip,st.o,st.h,st.l,st.c,st.body,st.range,
      st.spread,st.requested,st.entry,(st.entry-st.requested)*st.side/pip,st.initial_sl,st.r/pip,
      st.volume,base_balance*RiskPercent/100.0,st.risk,st.activation,
      st.entry>0?MathMax(0,(st.best-st.entry)*st.side/pip):0,
      st.entry>0?MathMax(0,(st.entry-st.worst)*st.side/pip):0,
      exitprice,grosspips,net,st.risk>0?net/st.risk:0,commission,swap,fee,st.recovered);
   FileFlush(csv);
}
void Reject(string reason) { Log("Senal descartada: "+reason); Event("REJECT",reason); }
void SaveState()
{
   if(testing) return;
   int f=FileOpen(state_file,FILE_BIN|FILE_WRITE);
   if(f==INVALID_HANDLE) { Log("ERROR persistencia estado "+IntegerToString(GetLastError())); return; }
   FileWriteStruct(f,st); FileFlush(f); FileClose(f);
}
bool LoadState()
{
   if(testing || !FileIsExist(state_file)) return false;
   int f=FileOpen(state_file,FILE_BIN|FILE_READ);
   if(f==INVALID_HANDLE) return false;
   uint n=FileReadStruct(f,st); FileClose(f);
   return n==sizeof(st) && st.version==1;
}
bool IsEURUSD(string symbol)
{
   return SymbolInfoString(symbol,SYMBOL_CURRENCY_BASE)=="EUR" &&
          SymbolInfoString(symbol,SYMBOL_CURRENCY_PROFIT)=="USD";
}
bool AnyPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(PositionGetTicket(i)>0 && IsEURUSD(PositionGetString(POSITION_SYMBOL))) return true;
   return false;
}
ulong OwnPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t>0 && PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber) return t;
   }
   return 0;
}
bool BusyOrder()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderGetTicket(i)>0 && OrderGetString(ORDER_SYMBOL)==_Symbol &&
         (ulong)OrderGetInteger(ORDER_MAGIC)==MagicNumber) return true;
   return pending;
}
double Grid(double price) { return NormalizeDouble(MathRound(price/tick_size)*tick_size,digits); }
bool OnGrid(double p) { return MathAbs(p-Grid(p))<tick_size*1e-6; }

// R nunca se reconstruye usando POSITION_SL: se usa DEAL_SL de entrada.
bool Recover(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;
   ulong id=(ulong)PositionGetInteger(POSITION_IDENTIFIER);
   if(st.id==id && st.r>0 &&
      MathAbs(st.entry-PositionGetDouble(POSITION_PRICE_OPEN))<tick_size*1e-7 &&
      PositionGetDouble(POSITION_VOLUME)<=st.volume+1e-9) return true;
   if(st.id==id) st.id=0; // Reconciliar precio medio/volumen de varios fills de una unica orden.
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   double vol=PositionGetDouble(POSITION_VOLUME);
   int side=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1;
   datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
   if(!HistorySelectByPosition(id)) return false;
   double sl=0;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong d=HistoryDealGetTicket(i);
      if(HistoryDealGetInteger(d,DEAL_ENTRY)==DEAL_ENTRY_IN)
      { sl=HistoryDealGetDouble(d,DEAL_SL); break; }
   }
   if(sl<=0 || (entry-sl)*side<=0) { Log("ERROR: imposible recuperar SL original; sin modificar posicion"); return false; }
   // Una apertura recien enviada conserva los datos de la senal.
   bool fresh=(st.id==0 && st.initial_sl>0 && MathAbs(st.initial_sl-sl)<tick_size/2);
   if(!fresh) { ZeroMemory(st); st.recovered=1; }
   st.version=1; st.id=id; st.side=side; st.opened=opened;
   st.entry=entry; st.initial_sl=sl; st.r=MathAbs(entry-sl); st.volume=vol;
   st.trail_distance=st.r*TrailingDistanceRR; st.activation_distance=st.r*TrailingActivationRR;
   st.best=entry; st.worst=entry;
   double profit=0;
   if(OrderCalcProfit(side==1?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,vol,entry,sl,profit)) st.risk=MathAbs(profit);
   PositionSelectByTicket(ticket);
   double current=PositionGetDouble(POSITION_SL);
   if(current>0 && (current-sl)*side>tick_size/2)
   {
      st.active=1; st.moved=1;
      st.best=current+side*st.trail_distance;
   }
   SaveState(); Event("OPEN",fresh?"EXECUTED":"RECOVERED_HISTORY_METRICS_INCOMPLETE");
   Log("Posicion "+U(id)+" R="+DoubleToString(st.r/pip,5)+" pips; riesgo efectivo="+DoubleToString(st.risk,2));
   if(st.risk>base_balance*RiskPercent/100.0+0.01) Log("Riesgo efectivo supera presupuesto por ejecucion/conversion");
   if(current<=0 || ((entry-current)*side<=0 && !st.moved)) Log("ANOMALIA SL tras ejecucion; no se fuerza cierre ni se amplia SL");
   return true;
}
void ReportClosed()
{
   if(st.id==0 || !HistorySelectByPosition(st.id)) return;
   double net=0,comm=0,swap=0,fee=0,weighted=0,outvol=0;
   datetime closed=0; long reason=-1;
   for(int i=0;i<HistoryDealsTotal();i++)
   {
      ulong d=HistoryDealGetTicket(i);
      net+=HistoryDealGetDouble(d,DEAL_PROFIT);
      comm+=HistoryDealGetDouble(d,DEAL_COMMISSION);
      swap+=HistoryDealGetDouble(d,DEAL_SWAP); fee+=HistoryDealGetDouble(d,DEAL_FEE);
      long e=HistoryDealGetInteger(d,DEAL_ENTRY);
      if(e==DEAL_ENTRY_OUT || e==DEAL_ENTRY_OUT_BY || e==DEAL_ENTRY_INOUT)
      {
         double v=HistoryDealGetDouble(d,DEAL_VOLUME);
         outvol+=v; weighted+=v*HistoryDealGetDouble(d,DEAL_PRICE);
         closed=(datetime)HistoryDealGetInteger(d,DEAL_TIME); reason=HistoryDealGetInteger(d,DEAL_REASON);
      }
   }
   if(outvol<=0) return;
   net+=comm+swap+fee;
   double exitprice=weighted/outvol,pips=(exitprice-st.entry)*st.side/pip;
   if((exitprice-st.best)*st.side>0) st.best=exitprice;
   if((exitprice-st.worst)*st.side>0) st.worst=exitprice;
   string why=EnumToString((ENUM_DEAL_REASON)reason);
   if(reason==DEAL_REASON_SL)
   {
      if(!st.moved) why="INITIAL_SL";
      else if(net<0) why=pips< -1e-7?"TRAILING_LOSS_EXECUTION":"TRAILING_NET_LOSS_COSTS";
      else if(MathAbs(net)<1e-8) why="TRAILING_BREAKEVEN_NET";
      else why="TRAILING_PROFIT_NET";
   }
   Event("CLOSE",why,net,pips,comm,swap,fee,closed,exitprice);
   Log("Cierre "+U(st.id)+" "+why+" neto="+DoubleToString(net,2));
   last_closed_id=st.id; ZeroMemory(st); SaveState();
}
void Manage(const MqlTick &q)
{
   ulong ticket=OwnPosition();
   if(ticket==0) { if(!pending) ReportClosed(); return; }
   pending=false;
   if(!Recover(ticket) || !PositionSelectByTicket(ticket)) return;
   double px=st.side==1?q.bid:q.ask;
   bool changed=false;
   if((px-st.best)*st.side>0) { st.best=px; changed=true; }
   if((px-st.worst)*st.side<0) { st.worst=px; changed=true; }
   if(!st.active && (st.best-st.entry)*st.side+tick_size*1e-7>=st.activation_distance)
   { st.active=1; st.activation=px; changed=true; Event("TRAIL_ACTIVATE","1R_OR_CONFIGURED_RR"); }
   if(changed) SaveState();
   if(!st.active) return;
   double raw=st.best-st.side*st.trail_distance;
   // Redondeo al tick mas cercano: no se amplia la distancia para sortear restricciones.
   double next=Grid(raw),old=PositionGetDouble(POSITION_SL);
   if(old>0 && (next-old)*st.side<tick_size*(1-1e-7)) return;
   double stops=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*point;
   double freeze=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL)*point;
   double distance=(px-next)*st.side;
   if(distance<=0 || distance+point*1e-7<stops || distance<=freeze ||
      (old>0 && freeze>0 && (px-old)*st.side<=freeze))
   {
      if(!trailing_block_logged) Log("Trailing diferido: stops/freeze; se conserva SL");
      trailing_block_logged=true;
      return;
   }
   trailing_block_logged=false;
   MqlTradeRequest req={}; MqlTradeResult res={};
   req.action=TRADE_ACTION_SLTP; req.position=ticket; req.symbol=_Symbol;
   req.magic=MagicNumber; req.sl=next; req.tp=0;
   bool sent=OrderSend(req,res);
   if(sent && res.retcode==TRADE_RETCODE_DONE)
   { st.moved=1; SaveState(); Event("TRAIL_MOVE",DoubleToString(next,digits)); }
   else Log("Modificacion SL rechazada: "+IntegerToString(res.retcode)+" "+res.comment);
}

bool Signal(datetime boundary)
{
   MqlRates bars[];
   if(CopyRates(_Symbol,PERIOD_M1,1,1,bars)!=1 || bars[0].time+60!=boundary)
   { if(EnableDebugLogs) Log("M1 insuficiente/no contigua"); return false; }
   // Se busca la M15 que contiene boundary y luego la anterior, ya confirmada.
   int shift=iBarShift(_Symbol,PERIOD_M15,boundary,false);
   if(shift<0) return false;
   datetime mt=iTime(_Symbol,PERIOD_M15,shift);
   if(mt<=0 || mt>boundary) return false;
   if(mt+PeriodSeconds(PERIOD_M15)>boundary) shift++;
   mt=iTime(_Symbol,PERIOD_M15,shift);
   double ema[];
   if(mt<=0 || mt+900>boundary || BarsCalculated(ema_handle)<shift+EMA_Period ||
      CopyBuffer(ema_handle,0,shift,1,ema)!=1 || !MathIsValidNumber(ema[0]) || ema[0]==EMPTY_VALUE) return false;
   double range=bars[0].high-bars[0].low,body=MathAbs(bars[0].close-bars[0].open);
   if(range<=0) return false;
   // Tolerancia solo para error binario: un rango exactamente igual se rechaza.
   double eps=tick_size*1e-7;
   if(range-MinCandleRangePips*pip<=eps ||
      (MaxCandleRangePips>0 && range-MaxCandleRangePips*pip>eps) ||
      body*100+eps<MinBodyPercent*range) return false;
   int side=0;
   if(bars[0].close>bars[0].open && bars[0].close<ema[0]) side=1;
   if(bars[0].close<bars[0].open && bars[0].close>ema[0]) side=-1;
   if(side==0) return false;
   ZeroMemory(st); st.version=1; st.side=side; st.signal_time=bars[0].time;
   st.o=bars[0].open; st.h=bars[0].high; st.l=bars[0].low; st.c=bars[0].close;
   st.body=100*body/range; st.range=range/pip; st.ema=ema[0];
   st.initial_sl=side==1?st.l:st.h;
   return true;
}
void Enter(const MqlTick &q)
{
   st.spread=(q.ask-q.bid)/pip; st.requested=st.side==1?q.ask:q.bid;
   if(UseSpreadFilter && st.spread>MaxSpreadPips+1e-9) { Reject("SPREAD"); return; }
   if(AnyPosition() || BusyOrder()) { Reject("POSITION_OR_ORDER_EXISTS"); return; }
   double sl=st.initial_sl,px=st.requested;
   double stopdistance=(st.side==1?q.bid-sl:sl-q.ask);
   double minstop=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*point;
   if(!OnGrid(sl) || (px-sl)*st.side<=0 || stopdistance<=0 || stopdistance+point*1e-7<minstop)
   { Reject("INVALID_SL"); return; }
   ENUM_ORDER_TYPE type=st.side==1?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double loss=0,minvol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxvol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX),step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   // Usar volumen permitido como referencia evita asumir que 1 lote esta permitido.
   if(minvol<=0 || step<=0 || !OrderCalcProfit(type,_Symbol,minvol,px,sl,loss) || loss>=0)
   { Reject("VOLUME_PROFIT_CALC"); return; }
   double budget=base_balance*RiskPercent/100.0,perlot=-loss/minvol;
   double volume=NormalizeDouble(MathFloor(MathMin(maxvol,budget/perlot)/step)*step,8);
   while(volume>0 && volume*perlot>budget) volume=NormalizeDouble(volume-step,8);
   if(volume<minvol || volume<=0) { Reject("VOLUME_MIN_EXCEEDS_BUDGET"); return; }
   double margin=0;
   if(!OrderCalcMargin(type,_Symbol,volume,px,margin) || margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   { Reject("INSUFFICIENT_MARGIN"); return; }
   MqlTradeRequest req={}; MqlTradeResult res={}; MqlTradeCheckResult check={};
   req.action=TRADE_ACTION_DEAL; req.symbol=_Symbol; req.magic=MagicNumber;
   req.volume=volume; req.type=type; req.price=px; req.sl=sl; req.tp=0;
   req.deviation=MaxSlippagePoints; req.comment="EMA200 MR V1";
   long fill=SymbolInfoInteger(_Symbol,SYMBOL_FILLING_MODE);
   if((fill&SYMBOL_FILLING_FOK)!=0) req.type_filling=ORDER_FILLING_FOK;
   else if((fill&SYMBOL_FILLING_IOC)!=0) req.type_filling=ORDER_FILLING_IOC;
   else { Reject("NO_FOK_IOC_FILLING"); return; } // No dejar remanentes pendientes.
   if(!OrderCheck(req,check) || (check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE)) { Reject("ORDER_CHECK "+IntegerToString(check.retcode)+" "+check.comment); return; }
   st.volume=volume; SaveState(); pending=true;
   bool sent=OrderSend(req,res); pending_order=res.order;
   Log("OrderSend bool="+IntegerToString(sent)+" retcode="+IntegerToString(res.retcode)+" external="+IntegerToString(res.retcode_external)+" "+res.comment);
   if(!sent || (res.retcode!=TRADE_RETCODE_DONE && res.retcode!=TRADE_RETCODE_DONE_PARTIAL && res.retcode!=TRADE_RETCODE_PLACED))
   {
      // TIMEOUT/CONNECTION son ambiguos: no reenviar; reconciliar posiciones/ordenes.
      pending=(res.retcode==TRADE_RETCODE_TIMEOUT || res.retcode==TRADE_RETCODE_CONNECTION);
      Reject("EXECUTION "+IntegerToString(res.retcode)); return;
   }
   ulong ticket=OwnPosition();
   if(ticket>0) { pending=false; Recover(ticket); }
}

int OnInit()
{
   testing=(bool)MQLInfoInteger(MQL_TESTER);
   digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   point=SymbolInfoDouble(_Symbol,SYMBOL_POINT); tick_size=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   pip=0.0001;
   if(!IsEURUSD(_Symbol) || (digits!=4 && digits!=5) || tick_size<=0 || point<=0 ||
      EMA_Period<1 || MinBodyPercent<0 || MinBodyPercent>100 || MinCandleRangePips<0 ||
      MaxCandleRangePips<0 || RiskPercent<=0 || FixedInitialBalance<0 || MaxSpreadPips<0 ||
      TrailingActivationRR<=0 || TrailingDistanceRR<=0 || MaxOpenPositions<1 || MagicNumber==0)
      return INIT_PARAMETERS_INCORRECT;
   string identity=AccountInfoString(ACCOUNT_SERVER)+"_"+U((ulong)AccountInfoInteger(ACCOUNT_LOGIN))+"_"+_Symbol+"_"+U(MagicNumber);
   uint hash=2166136261;
   for(int j=0;j<StringLen(identity);j++) hash=(hash^(uint)StringGetCharacter(identity,j))*16777619;
   string stem="EMR1_"+U(hash);
   base_key=stem+"_base"; state_file=stem+"_state.bin";
   if(!testing)
   {
      string account=AccountInfoString(ACCOUNT_SERVER)+U((ulong)AccountInfoInteger(ACCOUNT_LOGIN));
      uint ah=2166136261;
      for(int j=0;j<StringLen(account);j++) ah=(ah^(uint)StringGetCharacter(account,j))*16777619;
      instance_lock=FileOpen("EMR1_EURUSD_"+U(ah)+".lock",FILE_BIN|FILE_READ|FILE_WRITE);
      if(instance_lock==INVALID_HANDLE) { Log("Ya existe una instancia EURUSD o no se puede adquirir bloqueo"); return INIT_FAILED; }
   }
   if(testing) base_balance=FixedInitialBalance>0?FixedInitialBalance:AccountInfoDouble(ACCOUNT_BALANCE);
   else
   {
      // Archivo persistente: no caduca como las variables globales del terminal.
      string bf=stem+"_capital.bin";
      if(FixedInitialBalance>0) base_balance=FixedInitialBalance;
      else if(FileIsExist(bf))
      {
         int f=FileOpen(bf,FILE_BIN|FILE_READ);
         if(f==INVALID_HANDLE) return INIT_FAILED;
         base_balance=FileReadDouble(f); FileClose(f);
      }
      else base_balance=AccountInfoDouble(ACCOUNT_BALANCE);
      int f=FileOpen(bf,FILE_BIN|FILE_WRITE);
      if(f==INVALID_HANDLE) return INIT_FAILED;
      FileWriteDouble(f,base_balance); FileFlush(f); FileClose(f);
   }
   if(base_balance<=0 || !MathIsValidNumber(base_balance)) return INIT_FAILED;
   ema_handle=iMA(_Symbol,PERIOD_M15,EMA_Period,0,MODE_EMA,PRICE_CLOSE);
   if(ema_handle==INVALID_HANDLE) return INIT_FAILED;
   if(ExportTradesCSV)
   {
      string name=stem+"_"+U((ulong)TimeLocal())+"_"+U(GetTickCount64())+".csv";
      csv=FileOpen(name,FILE_WRITE|FILE_CSV|FILE_ANSI,',');
      if(csv==INVALID_HANDLE) { IndicatorRelease(ema_handle); return INIT_FAILED; }
      FileWrite(csv,"event","reason","position_id","signal_time","open_time","close_time","side","ema","close_minus_ema_pips",
      "open","high","low","close","body_percent","range_pips","spread_pips","requested","executed","slippage_pips",
      "initial_sl","R_pips","volume","budget","effective_risk","activation_price","MFE_pips","MAE_pips","exit_price",
      "gross_pips","net_money","net_R","commission","swap","fee","recovered_incomplete_metrics");
      Log("CSV: MQL5/Files/"+name);
   }
   ZeroMemory(st);
   if(!LoadState()) ZeroMemory(st);
   ulong t=OwnPosition();
   if(t>0 && !Recover(t)) { Log("No se pudo reconstruir R"); return INIT_FAILED; }
   if(t==0 && st.id!=0) ReportClosed();
   // Arranque a mitad de vela: esperar siguiente M1, nunca operar retrospectivamente.
   last_bar=iTime(_Symbol,PERIOD_M1,0);
   Log("Inicializado; capital base="+DoubleToString(base_balance,2));
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   if(reason!=REASON_INITFAILED) SaveState();
   if(csv!=INVALID_HANDLE) FileClose(csv);
   if(ema_handle!=INVALID_HANDLE) IndicatorRelease(ema_handle);
   if(instance_lock!=INVALID_HANDLE) FileClose(instance_lock);
}
void OnTick()
{
   MqlTick q;
   if(!SymbolInfoTick(_Symbol,q) || q.bid<=0 || q.ask<=0) return;
   Manage(q);
   datetime bar=iTime(_Symbol,PERIOD_M1,0);
   if(bar<=0 || bar==last_bar) return;
   if(last_bar==0) { last_bar=bar; return; }
   last_bar=bar; // Consumir ANTES de leer datos/enviar; nunca reintentar una senal.
   if(q.time<bar || q.time>=bar+60) return;
   // No sobrescribir el estado de una posicion al registrar una senal descartada.
   TradeState saved=st;
   if(Signal(bar))
   {
      if(AnyPosition() || BusyOrder() || saved.id!=0) { Reject("POSITION_OR_ORDER_EXISTS_OR_HISTORY_PENDING"); st=saved; }
      else Enter(q);
   }
}
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(trans.symbol!=_Symbol) return;
   // El orden de notificacion no esta garantizado. Capturar entradas incluso
   // si la posicion ya se cerro antes de procesar su evento.
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD && HistoryDealSelect(trans.deal) &&
      (ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)==MagicNumber &&
      HistoryDealGetInteger(trans.deal,DEAL_ENTRY)==DEAL_ENTRY_IN)
   {
      ulong id=(ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
      if(st.id==0 && id!=last_closed_id && OwnPosition()==0 && HistorySelectByPosition(id))
      {
         double v=0,w=0,sl=0; datetime opened=0; int side=0;
         for(int i=0;i<HistoryDealsTotal();i++)
         {
            ulong d=HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(d,DEAL_ENTRY)!=DEAL_ENTRY_IN) continue;
            double dv=HistoryDealGetDouble(d,DEAL_VOLUME);
            v+=dv; w+=dv*HistoryDealGetDouble(d,DEAL_PRICE);
            sl=HistoryDealGetDouble(d,DEAL_SL);
            opened=(datetime)HistoryDealGetInteger(d,DEAL_TIME);
            side=HistoryDealGetInteger(d,DEAL_TYPE)==DEAL_TYPE_BUY?1:-1;
         }
         if(v>0 && sl>0)
         {
            st.version=1; st.id=id; st.entry=w/v; st.volume=v; st.initial_sl=sl;
            st.side=side; st.opened=opened; st.r=MathAbs(st.entry-sl);
            st.best=st.entry; st.worst=st.entry;
            st.trail_distance=st.r*TrailingDistanceRR; st.activation_distance=st.r*TrailingActivationRR;
            double pnl=0;
            if(OrderCalcProfit(side==1?ORDER_TYPE_BUY:ORDER_TYPE_SELL,_Symbol,v,st.entry,sl,pnl)) st.risk=MathAbs(pnl);
            pending=false; SaveState(); Event("OPEN","HISTORY_FAST_EXECUTION");
         }
      }
   }
   if(pending_order>0 && trans.order==pending_order && trans.type==TRADE_TRANSACTION_HISTORY_ADD) pending=false;
   MqlTick q;
   if(SymbolInfoTick(_Symbol,q)) Manage(q);
}
