//+------------------------------------------------------------------+
//|                                         CandleMomentumATR_EA.mq5 |
//|                                    Candle Behavior Research (MT5)|
//|                         https://github.com/d-kuperman/one-minute-candle |
//+------------------------------------------------------------------+
#property copyright "d-kuperman"
#property link      "https://github.com/d-kuperman/one-minute-candle"
#property version   "1.00"
#property strict
#property description "EA de continuación por vela de intención filtrada por múltiplo de ATR, con SL en extremo de vela y TP por Ratio Riesgo:Beneficio (RR)."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Enumeración de Temporalidades para el Probador de Estrategias    |
//+------------------------------------------------------------------+
enum ENUM_TF_ESTRATEGIA
  {
   TF_M1   = 0, // 1 min
   TF_M3   = 1, // 3 min
   TF_M5   = 2, // 5 min
   TF_M15  = 3, // 15 min
   TF_M30  = 4, // 30 min
   TF_M60  = 5, // 60 min
   TF_M120 = 6, // 120 min
   TF_M240 = 7  // 240 min
  };

//+------------------------------------------------------------------+
//| Parámetros de Entrada                                            |
//+------------------------------------------------------------------+
input ENUM_TF_ESTRATEGIA InpTimeframe        = TF_M1; // Temporalidad
input double             InpPorcentajeCuerpo = 80.0;  // 1. Porcentaje de cuerpo de la vela (%)
input double             InpMultiplicadorATR = 1.0;   // 2. Tamaño mínimo de la vela (Múltiplo de ATR, ej: 0.8, 1.0, 1.5)
input int                InpPeriodoATR       = 14;    // Período del ATR
input double             InpRiesgoPorcentaje = 1.0;   // 3. Riesgo por operación (% del Balance)
input double             InpRR               = 1.0;   // 4. RR (Ratio Riesgo:Beneficio)
input double             InpSpreadMax_Pips   = 1.0;   // 5. Spread filter (Máximo en Pips)

//+------------------------------------------------------------------+
//| Constantes y Variables Globales                                  |
//+------------------------------------------------------------------+
const ulong     MAGIC_NUMBER = 200350; // Magic Number exclusivo de este EA
CTrade          g_trade;
int             g_handleATR  = INVALID_HANDLE;
ENUM_TIMEFRAMES g_tfGatillo  = PERIOD_M1;
double          g_tamanoPip  = 0.0;
datetime        g_ultimaVela = 0;

//+------------------------------------------------------------------+
//| Convierte el selector personalizado a ENUM_TIMEFRAMES de MT5     |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES ConvertirTimeframe(ENUM_TF_ESTRATEGIA tf)
  {
   switch(tf)
     {
      case TF_M1:   return PERIOD_M1;
      case TF_M3:   return PERIOD_M3;
      case TF_M5:   return PERIOD_M5;
      case TF_M15:  return PERIOD_M15;
      case TF_M30:  return PERIOD_M30;
      case TF_M60:  return PERIOD_H1;
      case TF_M120: return PERIOD_H2;
      case TF_M240: return PERIOD_H4;
      default:      return PERIOD_M1;
     }
  }

//+------------------------------------------------------------------+
//| Calcula el valor de 1 Pip en unidades de precio del símbolo      |
//+------------------------------------------------------------------+
double CalcularTamanoPip()
  {
   // Metales preciosos (XAU / GOLD) de 2 o 3 decimales: 1 Pip = 0.10
   if((_Digits == 2 || _Digits == 3) &&
      (StringFind(_Symbol, "XAU") >= 0 || StringFind(_Symbol, "GOLD") >= 0))
      return _Point * 10.0;

   // Pares Forex y activos con 3 o 5 decimales: 1 Pip = 10 puntos
   if(_Digits == 3 || _Digits == 5)
      return _Point * 10.0;

   // Pares Forex de 2 o 4 decimales y otros instrumentos
   return _Point;
  }

//+------------------------------------------------------------------+
//| Cuantiza un precio al TickSize del símbolo y a sus decimales     |
//+------------------------------------------------------------------+
double AlinearPrecio(double precio, double tickSize)
  {
   if(tickSize > 0.0)
      precio = MathRound(precio / tickSize) * tickSize;
   return NormalizeDouble(precio, _Digits);
  }

//+------------------------------------------------------------------+
//| Obtiene la cantidad de decimales correspondiente al Volume Step  |
//+------------------------------------------------------------------+
int ObtenerDigitosVolumen(double volStep)
  {
   if(volStep <= 0.0)
      return 2;

   int digitos = 0;
   double temp = volStep;
   while(digitos < 8 && MathAbs(temp - MathRound(temp)) > 1e-7)
     {
      temp *= 10.0;
      digitos++;
     }
   return digitos;
  }

//+------------------------------------------------------------------+
//| Configura la política de Filling compatible con el símbolo       |
//+------------------------------------------------------------------+
bool ConfigurarFillingModo()
  {
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
     {
      g_trade.SetTypeFilling(ORDER_FILLING_FOK);
      return true;
     }
   if((filling & SYMBOL_FILLING_IOC) != 0)
     {
      g_trade.SetTypeFilling(ORDER_FILLING_IOC);
      return true;
     }

   ENUM_SYMBOL_TRADE_EXECUTION execMode = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_EXEMODE);
   if(execMode != SYMBOL_TRADE_EXECUTION_MARKET)
     {
      g_trade.SetTypeFilling(ORDER_FILLING_RETURN);
      return true;
     }

   return false;
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpPorcentajeCuerpo <= 0.0 || InpPorcentajeCuerpo > 100.0)
     {
      Print("Error de parámetros: El porcentaje de cuerpo debe estar entre 0 (exclusivo) y 100.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMultiplicadorATR <= 0.0)
     {
      Print("Error de parámetros: El multiplicador de ATR debe ser mayor a 0.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpPeriodoATR < 1)
     {
      Print("Error de parámetros: El período del ATR debe ser >= 1.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRiesgoPorcentaje <= 0.0)
     {
      Print("Error de parámetros: El riesgo por operación debe ser mayor a 0.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRR <= 0.0)
     {
      Print("Error de parámetros: El ratio RR debe ser mayor a 0.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpSpreadMax_Pips < 0.0)
     {
      Print("Error de parámetros: El filtro de spread no puede ser negativo.");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(_Point <= 0.0 || SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE) <= 0.0)
     {
      Print("Error de inicialización: Especificaciones de precio/tick inválidas para ", _Symbol);
      return INIT_FAILED;
     }

   g_trade.SetExpertMagicNumber(MAGIC_NUMBER);
   if(!ConfigurarFillingModo())
     {
      Print("Error de inicialización: Modo de ejecución/filling no soportado para ", _Symbol);
      return INIT_FAILED;
     }
   g_trade.SetMarginMode();

   g_tfGatillo = ConvertirTimeframe(InpTimeframe);
   g_tamanoPip = CalcularTamanoPip();

   g_handleATR = iATR(_Symbol, g_tfGatillo, InpPeriodoATR);
   if(g_handleATR == INVALID_HANDLE)
     {
      Print("Error al crear el handle de ATR. Código: ", GetLastError());
      return INIT_FAILED;
     }

   g_ultimaVela = iTime(_Symbol, g_tfGatillo, 0);

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_handleATR != INVALID_HANDLE)
     {
      IndicatorRelease(g_handleATR);
      g_handleATR = INVALID_HANDLE;
     }
  }

//+------------------------------------------------------------------+
//| Cuenta las posiciones abiertas por este EA en el símbolo actual  |
//+------------------------------------------------------------------+
void ContarPosicionesAbiertas(int &comprasAbiertas, int &ventasAbiertas)
  {
   comprasAbiertas = 0;
   ventasAbiertas  = 0;

   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != MAGIC_NUMBER)
         continue;

      ENUM_POSITION_TYPE tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(tipo == POSITION_TYPE_BUY)
         comprasAbiertas++;
      else if(tipo == POSITION_TYPE_SELL)
         ventasAbiertas++;
     }
  }

//+------------------------------------------------------------------+
//| Verifica si el spread actual es igual o menor al filtro          |
//+------------------------------------------------------------------+
bool CumpleFiltroSpread(double ask, double bid)
  {
   double spreadActual = ask - bid;
   double spreadMaximo = InpSpreadMax_Pips * g_tamanoPip;
   double epsPrecio    = _Point * 1e-4;

   return (spreadActual <= spreadMaximo + epsPrecio);
  }

//+------------------------------------------------------------------+
//| Calcula el lotaje según el riesgo monetario entre Entrada y SL   |
//+------------------------------------------------------------------+
double CalcularLotajePorRiesgo(ENUM_ORDER_TYPE tipoOrden, double precioEntrada, double precioSL)
  {
   double distanciaSL = MathAbs(precioEntrada - precioSL);
   if(distanciaSL <= 0.0)
      return 0.0;

   double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
   double montoRiesgo = balance * (InpRiesgoPorcentaje / 100.0);
   if(montoRiesgo <= 0.0)
      return 0.0;

   double tickSize    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double volMin      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volStep     = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(tickSize <= 0.0 || volStep <= 0.0 || volMin <= 0.0)
      return 0.0;

   // Calcular la pérdida exacta de 1.0 lote usando OrderCalcProfit
   double perdidaPorLote = 0.0;
   double beneficioCalc  = 0.0;
   if(OrderCalcProfit(tipoOrden, _Symbol, 1.0, precioEntrada, precioSL, beneficioCalc) && beneficioCalc < 0.0)
     {
      perdidaPorLote = MathAbs(beneficioCalc);
     }
   else
     {
      double tickValueLoss = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tickValueLoss <= 0.0)
         tickValueLoss = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tickValueLoss <= 0.0)
         return 0.0;

      perdidaPorLote = (distanciaSL / tickSize) * tickValueLoss;
     }

   if(perdidaPorLote <= 0.0)
      return 0.0;

   double lotes = montoRiesgo / perdidaPorLote;

   // Ajustar al paso de volumen (con tolerancia IEEE 754 para evitar truncamiento espurio)
   double pasos = MathFloor((lotes / volStep) + 1e-7);
   lotes = pasos * volStep;

   if(lotes < volMin)
      lotes = volMin;
   if(lotes > volMax)
      lotes = volMax;

   // Respetar límite de volumen agregado del símbolo si existe
   double volLimit = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_LIMIT);
   if(volLimit > 0.0)
     {
      double volumenActual = 0.0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         if(PositionGetTicket(i) != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol)
            volumenActual += PositionGetDouble(POSITION_VOLUME);
        }
      double disponible = volLimit - volumenActual;
      if(disponible < volMin - 1e-7)
         return 0.0;
      if(lotes > disponible)
         lotes = MathFloor((disponible / volStep) + 1e-7) * volStep;
     }

   // Verificar margen libre para evitar rechazos por falta de margen en SL cortos
   double margenLibre     = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double margenRequerido = 0.0;
   if(margenLibre > 0.0 && OrderCalcMargin(tipoOrden, _Symbol, lotes, precioEntrada, margenRequerido))
     {
      if(margenRequerido > margenLibre && margenRequerido > 0.0)
        {
         double factor   = (margenLibre * 0.95) / margenRequerido;
         double lotesMax = MathFloor(((lotes * factor) / volStep) + 1e-7) * volStep;
         if(lotesMax < volMin)
            return 0.0;
         lotes = lotesMax;
        }
     }

   int digitosLote = ObtenerDigitosVolumen(volStep);
   return NormalizeDouble(lotes, digitosLote);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Verificar apertura de una nueva vela en la temporalidad seleccionada
   datetime tiempoVelaActual = iTime(_Symbol, g_tfGatillo, 0);
   if(tiempoVelaActual == 0)
      return;

   // Evitar evaluación a mitad de vela si el historial aún no estaba listo en OnInit
   if(g_ultimaVela == 0)
     {
      g_ultimaVela = tiempoVelaActual;
      return;
     }

   if(tiempoVelaActual == g_ultimaVela)
      return;

   // 2. Obtener los datos de la vela recién cerrada (índice 1) y el ATR (índice 1)
   if(BarsCalculated(g_handleATR) < InpPeriodoATR)
      return;

   MqlRates vela[1];
   if(CopyRates(_Symbol, g_tfGatillo, 1, 1, vela) < 1)
      return;

   double bufATR[1];
   if(CopyBuffer(g_handleATR, 0, 1, 1, bufATR) < 1)
      return;

   double atrValor = bufATR[0];
   if(!MathIsValidNumber(atrValor) || atrValor == EMPTY_VALUE || atrValor <= 0.0)
      return;

   // Marcar la vela actual como procesada una vez confirmadas ambas lecturas
   g_ultimaVela = tiempoVelaActual;

   // 3. Obtener cotización actual validada
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;
   if(!MathIsValidNumber(tick.bid) || !MathIsValidNumber(tick.ask) ||
      tick.bid <= 0.0 || tick.ask <= 0.0 || tick.ask < tick.bid)
      return;

   double ask = tick.ask;
   double bid = tick.bid;

   // 4. Validar filtro de Spread (debe ser <= InpSpreadMax_Pips)
   if(!CumpleFiltroSpread(ask, bid))
      return;

   // 5. Evaluar las características de la vela cerrada (índice 1)
   double highVela  = vela[0].high;
   double lowVela   = vela[0].low;
   double openVela  = vela[0].open;
   double closeVela = vela[0].close;

   double rangoVela = highVela - lowVela;
   if(rangoVela <= 0.0)
      return;

   double epsPrecio = _Point * 1e-4;

   // Validar tamaño total de la vela respecto al ATR: (High - Low) >= InpMultiplicadorATR * ATR
   double rangoMinPrecio = InpMultiplicadorATR * atrValor;
   if(rangoVela + epsPrecio < rangoMinPrecio)
      return;

   // Validar Porcentaje de cuerpo de la vela (Cuerpo / Rango >= InpPorcentajeCuerpo)
   double cuerpoVela       = MathAbs(closeVela - openVela);
   double porcentajeCuerpo = (cuerpoVela / rangoVela) * 100.0;
   if(porcentajeCuerpo + 1e-7 < InpPorcentajeCuerpo)
      return;

   bool esVelaAlcista = (closeVela > openVela);
   bool esVelaBajista = (closeVela < openVela);
   if(!esVelaAlcista && !esVelaBajista)
      return;

   // 6. Verificar posiciones abiertas (permitir simultáneas solo en la misma dirección)
   int comprasAbiertas = 0;
   int ventasAbiertas  = 0;
   ContarPosicionesAbiertas(comprasAbiertas, ventasAbiertas);

   double tickSize        = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   long   stopsLevel      = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double distMinSL       = (double)stopsLevel * _Point;
   double distMinEfectiva = MathMax(distMinSL, tickSize);

   // 7. Ejecutar orden a mercado en el sentido de la vela con SL en extremo y TP según RR
   if(esVelaAlcista)
     {
      // Si hay ventas abiertas, no abrir compra en sentido contrario
      if(ventasAbiertas > 0)
         return;

      double slCompra   = AlinearPrecio(lowVela, tickSize);
      double distanciaR = ask - slCompra;

      // Validar que el SL esté por debajo del Bid respetando el StopsLevel del broker
      if(distanciaR <= 0.0 || (bid - slCompra) + epsPrecio < distMinEfectiva)
         return;

      double tpCompra = AlinearPrecio(ask + (distanciaR * InpRR), tickSize);
      if((tpCompra - ask) + epsPrecio < distMinEfectiva)
         return;

      double lotes = CalcularLotajePorRiesgo(ORDER_TYPE_BUY, ask, slCompra);
      if(lotes <= 0.0)
         return;

      g_trade.Buy(lotes, _Symbol, ask, slCompra, tpCompra, "CMATR|Buy");
     }
   else if(esVelaBajista)
     {
      // Si hay compras abiertas, no abrir venta en sentido contrario
      if(comprasAbiertas > 0)
         return;

      double slVenta    = AlinearPrecio(highVela, tickSize);
      double distanciaR = slVenta - bid;

      // Validar que el SL esté por encima del Ask respetando el StopsLevel del broker
      if(distanciaR <= 0.0 || (slVenta - ask) + epsPrecio < distMinEfectiva)
         return;

      double tpVenta = AlinearPrecio(bid - (distanciaR * InpRR), tickSize);
      if((bid - tpVenta) + epsPrecio < distMinEfectiva)
         return;

      double lotes = CalcularLotajePorRiesgo(ORDER_TYPE_SELL, bid, slVenta);
      if(lotes <= 0.0)
         return;

      g_trade.Sell(lotes, _Symbol, bid, slVenta, tpVenta, "CMATR|Sell");
     }
  }
//+------------------------------------------------------------------+
