//+------------------------------------------------------------------+
//|                                           OneMinuteCandle_EA.mq5 |
//|                                    Candle Behavior Research (MT5)|
//|                         https://github.com/d-kuperman/one-minute-candle |
//+------------------------------------------------------------------+
#property copyright "d-kuperman"
#property link      "https://github.com/d-kuperman/one-minute-candle"
#property version   "1.00"
#property strict
#property description "Asesor Experto basado en velas de intención (cuerpo amplio) y retorno/tendencia respecto a 1 o 2 EMAs multi-temporalidad."

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Enumeraciones Personalizadas para el Probador de Estrategias     |
//+------------------------------------------------------------------+
enum ENUM_CANTIDAD_EMAS
  {
   CANT_EMA_1 = 1, // [1] Usar 1 EMA
   CANT_EMA_2 = 2  // [2] Usar 2 EMAs
  };

enum ENUM_TF_ESTRATEGIA
  {
   TF_M1  = 0, // M1 (1 Minuto)
   TF_M3  = 1, // M3 (3 Minutos)
   TF_M5  = 2, // M5 (5 Minutos)
   TF_M15 = 3, // M15 (15 Minutos)
   TF_M30 = 4, // M30 (30 Minutos)
   TF_H1  = 5, // H1 (1 Hora)
   TF_H4  = 6  // H4 (4 Horas)
  };

enum ENUM_MODO_DIRECCION
  {
   DIRECCION_REVERSION   = 0, // Reversión a la EMA (Debajo=Compra / Encima=Venta)
   DIRECCION_A_FAVOR     = 1, // A favor de la EMA (Encima=Compra / Debajo=Venta)
   DIRECCION_IGNORAR_EMA = 2  // Ignorar EMA (Operar ambas direcciones según vela)
  };

enum ENUM_MODO_PIPS
  {
   MODO_PIPS_AUTO  = 0, // Pips Estándar (Auto Forex/Metales/CFDs)
   MODO_PUNTOS_MT5 = 1  // Puntos Puros de MT5 (_Point)
  };

//+------------------------------------------------------------------+
//| Parámetros de Entrada (Inputs)                                   |
//+------------------------------------------------------------------+
input group "=== 1. Filtro de Dirección y EMAs ==="
input ENUM_MODO_DIRECCION InpModoDireccion       = DIRECCION_REVERSION; // Condición de Dirección
input ENUM_CANTIDAD_EMAS  InpCantidadEMAs        = CANT_EMA_1;          // Cantidad de EMAs a considerar [1 o 2]
input ENUM_TF_ESTRATEGIA  InpEMA1_Timeframe      = TF_M15;              // Temporalidad EMA [1]
input int                 InpEMA1_Periodo        = 200;                 // Periodos EMA [1]
input ENUM_TF_ESTRATEGIA  InpEMA2_Timeframe      = TF_H1;               // Temporalidad EMA [2]
input int                 InpEMA2_Periodo        = 200;                 // Periodos EMA [2]
input double              InpDistMinEMA_Pips     = 0.0;                 // Distancia mínima a la EMA en Pips (0 = Desactivado)

input group "=== 2. Configuración de Vela Gatillo ==="
input ENUM_TF_ESTRATEGIA  InpGatillo_Timeframe   = TF_M1;               // Temporalidad Vela Gatillo
input double              InpPorcentajeCuerpo    = 80.0;                // % Mínimo del Cuerpo de la Vela (0-100)
input double              InpRangoMin_Pips       = 2.5;                 // Rango de Precio Mínimo (High-Low en Pips)
input double              InpRangoMax_Pips       = 0.0;                 // Rango de Precio Máximo en Pips (0 = Sin límite)

input group "=== 3. Gestión de Riesgo, BE y Trailing Stop ==="
input double              InpRiesgoPorcentaje    = 1.0;                 // Tamaño de Posición (% del Balance Actual)
input double              InpAjusteBE_R          = 0.0;                 // Ajuste del BE sobre 1:1 (Ej: -0.2 = 0.8R, +0.5 = 1.5R)
input double              InpAjusteTrailing_R    = 0.0;                 // Ajuste Trailing Stop sobre 1:1 (Ej: -0.2 = 0.8R, +0.5 = 1.5R)

input group "=== 4. Filtros Operativos y Multi-Instrumento ==="
input bool                InpPermitirSimultaneas = false;               // Permitir Operaciones Simultáneas (misma dirección)
input double              InpSpreadMax_Pips      = 0.0;                 // Spread Máximo en Pips (0 = Desactivado)
input bool                InpUsarFiltroHorario   = false;               // Activar Filtro de Horario
input int                 InpHoraInicio          = 8;                   // Hora de Inicio (0-23)
input int                 InpMinInicio           = 0;                   // Minuto de Inicio (0-59)
input int                 InpHoraFin             = 20;                  // Hora de Fin (0-23)
input int                 InpMinFin              = 0;                   // Minuto de Fin (0-59)
input ENUM_MODO_PIPS      InpModoPips            = MODO_PIPS_AUTO;      // Modo de Medición de Pips
input ulong               InpMagicNumber         = 200150;              // Magic Number del EA

//+------------------------------------------------------------------+
//| Estructura para conservar el Riesgo Inicial (1R) de cada orden   |
//+------------------------------------------------------------------+
struct DatosPosicionRiesgo
  {
   ulong             ticket;       // Ticket de la posición
   double            riesgoInicial;// Distancia 1R en precio (|Entrada - SL_Inicial|)
  };

//+------------------------------------------------------------------+
//| Variables Globales                                               |
//+------------------------------------------------------------------+
CTrade               g_trade;
int                  g_handleEMA1        = INVALID_HANDLE;
int                  g_handleEMA2        = INVALID_HANDLE;
ENUM_TIMEFRAMES      g_tfEMA1            = PERIOD_M15;
ENUM_TIMEFRAMES      g_tfEMA2            = PERIOD_H1;
ENUM_TIMEFRAMES      g_tfGatillo         = PERIOD_M1;
double               g_tamanoPip         = 0.0;
datetime             g_ultimaVelaGatillo = 0;
DatosPosicionRiesgo  g_registroRiesgo[];

//+------------------------------------------------------------------+
//| Convierte el selector personalizado a ENUM_TIMEFRAMES de MT5     |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES ConvertirTimeframe(ENUM_TF_ESTRATEGIA tf)
  {
   switch(tf)
     {
      case TF_M1:  return PERIOD_M1;
      case TF_M3:  return PERIOD_M3;
      case TF_M5:  return PERIOD_M5;
      case TF_M15: return PERIOD_M15;
      case TF_M30: return PERIOD_M30;
      case TF_H1:  return PERIOD_H1;
      case TF_H4:  return PERIOD_H4;
      default:     return PERIOD_M1;
     }
  }

//+------------------------------------------------------------------+
//| Calcula el valor de 1 Pip en unidades de precio del símbolo      |
//+------------------------------------------------------------------+
double CalcularTamanoPip()
  {
   if(InpModoPips == MODO_PUNTOS_MT5)
      return _Point;

   // En pares Forex/Metales con 3 o 5 decimales, 1 Pip equivale a 10 puntos
   if(_Digits == 3 || _Digits == 5)
      return _Point * 10.0;

   // En activos de 2 decimales (Oro, Índices, Cripto) o 4 decimales
   ENUM_SYMBOL_CALC_MODE calcMode = (ENUM_SYMBOL_CALC_MODE)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_CALC_MODE);
   if(calcMode == SYMBOL_CALC_MODE_FOREX || calcMode == SYMBOL_CALC_MODE_FOREX_NO_LEVERAGE)
     {
      if(_Digits == 2 || _Digits == 4)
         return _Point;
     }

   // Para metales/CFDs de 2 decimales donde el punto mínimo es 0.01 pero el pip suele ser 0.10
   if(_Digits == 2 && StringFind(_Symbol, "XAU") >= 0)
      return _Point * 10.0;

   return _Point;
  }

//+------------------------------------------------------------------+
//| Gestión del registro en memoria del riesgo 1R por ticket         |
//+------------------------------------------------------------------+
void GuardarRiesgoPosicion(ulong ticket, double riesgoPrecio)
  {
   if(ticket == 0 || riesgoPrecio <= 0.0)
      return;

   int total = ArraySize(g_registroRiesgo);
   for(int i = 0; i < total; i++)
     {
      if(g_registroRiesgo[i].ticket == ticket)
        {
         g_registroRiesgo[i].riesgoInicial = riesgoPrecio;
         return;
        }
     }

   ArrayResize(g_registroRiesgo, total + 1);
   g_registroRiesgo[total].ticket        = ticket;
   g_registroRiesgo[total].riesgoInicial = riesgoPrecio;
  }

//+------------------------------------------------------------------+
//| Obtiene el riesgo inicial (1R) de una posición abierta           |
//+------------------------------------------------------------------+
double ObtenerRiesgoPosicion(ulong ticket, double precioApertura, double slActual, string comentario)
  {
   int total = ArraySize(g_registroRiesgo);
   for(int i = 0; i < total; i++)
     {
      if(g_registroRiesgo[i].ticket == ticket)
         return g_registroRiesgo[i].riesgoInicial;
     }

   // Respaldo 1: Si el EA se reinició, intenta recuperar 1R desde el comentario "OMC|R:xxx"
   int posTag = StringFind(comentario, "OMC|R:");
   if(posTag >= 0)
     {
      string valorPuntosStr = StringSubstr(comentario, posTag + 6);
      long puntosR = StringToInteger(valorPuntosStr);
      if(puntosR > 0)
        {
         double riesgoRecuperado = (double)puntosR * _Point;
         GuardarRiesgoPosicion(ticket, riesgoRecuperado);
         return riesgoRecuperado;
        }
     }

   // Respaldo 2: Si el SL actual es distinto al precio de entrada, usar la distancia actual
   double distActual = MathAbs(precioApertura - slActual);
   if(slActual > 0.0 && distActual > (_Point * 0.5))
     {
      GuardarRiesgoPosicion(ticket, distActual);
      return distActual;
     }

   return 0.0;
  }

//+------------------------------------------------------------------+
//| Limpia del registro los tickets de posiciones que ya se cerraron |
//+------------------------------------------------------------------+
void LimpiarRegistroRiesgo()
  {
   int total = ArraySize(g_registroRiesgo);
   if(total == 0)
      return;

   for(int i = total - 1; i >= 0; i--)
     {
      if(!PositionSelectByTicket(g_registroRiesgo[i].ticket))
        {
         int ultimo = ArraySize(g_registroRiesgo) - 1;
         if(i < ultimo)
            g_registroRiesgo[i] = g_registroRiesgo[ultimo];
         ArrayResize(g_registroRiesgo, ultimo);
        }
     }
  }

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Validación de parámetros para evitar pases inválidos en el optimizador
   if(InpEMA1_Periodo < 1)
     {
      Print("Error de parámetros: InpEMA1_Periodo debe ser >= 1.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpCantidadEMAs == CANT_EMA_2 && InpEMA2_Periodo < 1)
     {
      Print("Error de parámetros: InpEMA2_Periodo debe ser >= 1.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpPorcentajeCuerpo <= 0.0 || InpPorcentajeCuerpo > 100.0)
     {
      Print("Error de parámetros: InpPorcentajeCuerpo debe estar entre 0 y 100.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRangoMin_Pips < 0.0)
     {
      Print("Error de parámetros: InpRangoMin_Pips no puede ser negativo.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRangoMax_Pips > 0.0 && InpRangoMax_Pips < InpRangoMin_Pips)
     {
      Print("Error de parámetros: InpRangoMax_Pips no puede ser menor que InpRangoMin_Pips.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRiesgoPorcentaje <= 0.0)
     {
      Print("Error de parámetros: InpRiesgoPorcentaje debe ser > 0.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if((1.0 + InpAjusteBE_R) <= 0.0 || (1.0 + InpAjusteTrailing_R) <= 0.0)
     {
      Print("Error de parámetros: El ratio de activación (1.0 + Ajuste) para BE y Trailing debe ser > 0.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpHoraInicio < 0 || InpHoraInicio > 23 || InpHoraFin < 0 || InpHoraFin > 23 ||
      InpMinInicio < 0  || InpMinInicio > 59  || InpMinFin < 0  || InpMinFin > 59)
     {
      Print("Error de parámetros: Horario fuera de rango válido.");
      return INIT_PARAMETERS_INCORRECT;
     }

   // Configurar CTrade
   g_trade.SetExpertMagicNumber(InpMagicNumber);
   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetMarginMode();

   // Convertir temporalidades
   g_tfEMA1    = ConvertirTimeframe(InpEMA1_Timeframe);
   g_tfEMA2    = ConvertirTimeframe(InpEMA2_Timeframe);
   g_tfGatillo = ConvertirTimeframe(InpGatillo_Timeframe);
   g_tamanoPip = CalcularTamanoPip();

   // Inicializar handles de EMAs solo si el filtro de dirección las utiliza
   if(InpModoDireccion != DIRECCION_IGNORAR_EMA)
     {
      g_handleEMA1 = iMA(_Symbol, g_tfEMA1, InpEMA1_Periodo, 0, MODE_EMA, PRICE_CLOSE);
      if(g_handleEMA1 == INVALID_HANDLE)
        {
         Print("Error al crear el handle de EMA 1. Código: ", GetLastError());
         return INIT_FAILED;
        }

      if(InpCantidadEMAs == CANT_EMA_2)
        {
         g_handleEMA2 = iMA(_Symbol, g_tfEMA2, InpEMA2_Periodo, 0, MODE_EMA, PRICE_CLOSE);
         if(g_handleEMA2 == INVALID_HANDLE)
           {
            Print("Error al crear el handle de EMA 2. Código: ", GetLastError());
            return INIT_FAILED;
           }
        }
     }

   // Registrar la vela actual para evaluar únicamente a partir del próximo cierre de vela
   g_ultimaVelaGatillo = iTime(_Symbol, g_tfGatillo, 0);

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_handleEMA1 != INVALID_HANDLE)
     {
      IndicatorRelease(g_handleEMA1);
      g_handleEMA1 = INVALID_HANDLE;
     }
   if(g_handleEMA2 != INVALID_HANDLE)
     {
      IndicatorRelease(g_handleEMA2);
      g_handleEMA2 = INVALID_HANDLE;
     }
  }

//+------------------------------------------------------------------+
//| Cuenta posiciones abiertas del EA y gestiona BE / Trailing       |
//+------------------------------------------------------------------+
void GestionarPosicionesYContar(int &comprasAbiertas, int &ventasAbiertas)
  {
   comprasAbiertas = 0;
   ventasAbiertas  = 0;

   int totalPosiciones = PositionsTotal();
   if(totalPosiciones == 0)
     {
      if(ArraySize(g_registroRiesgo) > 0)
         ArrayResize(g_registroRiesgo, 0);
      return;
     }

   double bid        = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask        = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   long   stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double distMinSL  = (double)stopsLevel * _Point;

   double ratioBE    = 1.0 + InpAjusteBE_R;
   double ratioTS    = 1.0 + InpAjusteTrailing_R;

   for(int i = totalPosiciones - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         continue;

      ENUM_POSITION_TYPE tipo          = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double             precioEntrada = PositionGetDouble(POSITION_PRICE_OPEN);
      double             slActual      = PositionGetDouble(POSITION_SL);
      double             tpActual      = PositionGetDouble(POSITION_TP);
      string             comentario    = PositionGetString(POSITION_COMMENT);

      if(tipo == POSITION_TYPE_BUY)
         comprasAbiertas++;
      else if(tipo == POSITION_TYPE_SELL)
         ventasAbiertas++;

      // Obtener el riesgo inicial (1R) de la posición
      double riesgo1R = ObtenerRiesgoPosicion(ticket, precioEntrada, slActual, comentario);
      if(riesgo1R <= 0.0)
         continue;

      double distActivacionBE  = ratioBE * riesgo1R;
      double distActivacionTS  = ratioTS * riesgo1R;
      double distPersecucionTS = MathMax(riesgo1R, distActivacionTS);

      if(tipo == POSITION_TYPE_BUY)
        {
         double recorridoFavor = bid - precioEntrada;
         double nuevoSL        = slActual;

         // 1. Verificar activación del Break Even (BE)
         if(recorridoFavor >= distActivacionBE)
           {
            if(slActual < precioEntrada - (_Point * 0.5) || slActual == 0.0)
               nuevoSL = precioEntrada;
           }

         // 2. Verificar activación del Trailing Stop (TS)
         if(recorridoFavor >= distActivacionTS)
           {
            double slTrailing = bid - distPersecucionTS;
            if(slTrailing > nuevoSL)
               nuevoSL = slTrailing;
           }

         nuevoSL = NormalizeDouble(nuevoSL, _Digits);

         // Actualizar SL solo si mejora la posición hacia arriba y respeta el StopsLevel del broker
         if(nuevoSL > slActual + (_Point * 0.5) && (bid - nuevoSL) >= distMinSL)
           {
            g_trade.PositionModify(ticket, nuevoSL, tpActual);
           }
        }
      else if(tipo == POSITION_TYPE_SELL)
        {
         double recorridoFavor = precioEntrada - ask;
         double nuevoSL        = slActual;

         // 1. Verificar activación del Break Even (BE)
         if(recorridoFavor >= distActivacionBE)
           {
            if(slActual > precioEntrada + (_Point * 0.5) || slActual == 0.0)
               nuevoSL = precioEntrada;
           }

         // 2. Verificar activación del Trailing Stop (TS)
         if(recorridoFavor >= distActivacionTS)
           {
            double slTrailing = ask + distPersecucionTS;
            if(nuevoSL == 0.0 || slTrailing < nuevoSL)
               nuevoSL = slTrailing;
           }

         nuevoSL = NormalizeDouble(nuevoSL, _Digits);

         // Actualizar SL solo si mejora la posición hacia abajo y respeta el StopsLevel del broker
         if(nuevoSL > 0.0 && (slActual == 0.0 || nuevoSL < slActual - (_Point * 0.5)) && (nuevoSL - ask) >= distMinSL)
           {
            g_trade.PositionModify(ticket, nuevoSL, tpActual);
           }
        }
     }

   LimpiarRegistroRiesgo();
  }

//+------------------------------------------------------------------+
//| Verifica si la hora actual está dentro del horario permitido     |
//+------------------------------------------------------------------+
bool EstaEnHorarioOperativo()
  {
   if(!InpUsarFiltroHorario)
      return true;

   MqlDateTime dt;
   TimeCurrent(dt);

   int minutosActual = dt.hour * 60 + dt.min;
   int minutosInicio = InpHoraInicio * 60 + InpMinInicio;
   int minutosFin    = InpHoraFin * 60 + InpMinFin;

   if(minutosInicio <= minutosFin)
      return (minutosActual >= minutosInicio && minutosActual <= minutosFin);
   else
      // Soporta sesiones nocturnas que cruzan la medianoche (ej. 22:00 a 06:00)
      return (minutosActual >= minutosInicio || minutosActual <= minutosFin);
  }

//+------------------------------------------------------------------+
//| Verifica si el spread actual cumple con el máximo permitido      |
//+------------------------------------------------------------------+
bool CumpleFiltroSpread(double ask, double bid)
  {
   if(InpSpreadMax_Pips <= 0.0)
      return true;

   double spreadActual = ask - bid;
   double spreadMaximo = InpSpreadMax_Pips * g_tamanoPip;

   return (spreadActual <= spreadMaximo);
  }

//+------------------------------------------------------------------+
//| Calcula el tamaño de posición (lotes) para cualquier instrumento |
//+------------------------------------------------------------------+
double CalcularLotajePorRiesgo(double distanciaSL)
  {
   if(distanciaSL <= 0.0)
      return 0.0;

   double balance       = AccountInfoDouble(ACCOUNT_BALANCE);
   double montoRiesgo   = balance * (InpRiesgoPorcentaje / 100.0);

   double tickSize      = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double volMin        = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double volMax        = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volStep       = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(tickSize <= 0.0 || tickValue <= 0.0 || volStep <= 0.0)
      return 0.0;

   double perdidaPorLote = (distanciaSL / tickSize) * tickValue;
   if(perdidaPorLote <= 0.0)
      return 0.0;

   double lotes = montoRiesgo / perdidaPorLote;

   // Ajustar al paso de volumen del contrato (Volume Step)
   lotes = MathFloor(lotes / volStep) * volStep;

   if(lotes < volMin)
      lotes = volMin;
   if(lotes > volMax)
      lotes = volMax;

   // Redondear según los decimales del volStep
   int digitosLote = 2;
   if(volStep >= 1.0)
      digitosLote = 0;
   else if(volStep >= 0.1)
      digitosLote = 1;
   else if(volStep >= 0.01)
      digitosLote = 2;
   else if(volStep >= 0.001)
      digitosLote = 3;

   return NormalizeDouble(lotes, digitosLote);
  }

//+------------------------------------------------------------------+
//| Obtiene el valor actual de las EMAs configuradas                 |
//+------------------------------------------------------------------+
bool ObtenerValoresEMA(double &ema1, double &ema2)
  {
   double buf1[1];
   if(CopyBuffer(g_handleEMA1, 0, 0, 1, buf1) < 1)
      return false;
   ema1 = buf1[0];

   if(InpCantidadEMAs == CANT_EMA_2)
     {
      double buf2[1];
      if(CopyBuffer(g_handleEMA2, 0, 0, 1, buf2) < 1)
         return false;
      ema2 = buf2[0];
     }
   else
     {
      ema2 = ema1;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Gestionar posiciones abiertas tick a tick (BE y Trailing Stop)
   int comprasAbiertas = 0;
   int ventasAbiertas  = 0;
   GestionarPosicionesYContar(comprasAbiertas, ventasAbiertas);

   // 2. Verificar si acaba de cerrar una nueva vela en la temporalidad gatillo
   datetime tiempoVelaActual = iTime(_Symbol, g_tfGatillo, 0);
   if(tiempoVelaActual == 0 || tiempoVelaActual == g_ultimaVelaGatillo)
      return;

   g_ultimaVelaGatillo = tiempoVelaActual;

   // 3. Validar regla de operaciones simultáneas antes de hacer más cálculos
   int totalAbiertas = comprasAbiertas + ventasAbiertas;
   if(!InpPermitirSimultaneas && totalAbiertas > 0)
      return;

   // 4. Validar filtro de horario
   if(!EstaEnHorarioOperativo())
      return;

   // 5. Validar filtro de spread
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(!CumpleFiltroSpread(ask, bid))
      return;

   // 6. Si el filtro de EMA y distancia mínima están activos, obtener EMAs primero
   double ema1 = 0.0;
   double ema2 = 0.0;
   if(InpModoDireccion != DIRECCION_IGNORAR_EMA)
     {
      if(!ObtenerValoresEMA(ema1, ema2))
         return;

      // Optimización: Si hay distancia mínima configurada, descartar de inmediato si está muy cerca
      if(InpDistMinEMA_Pips > 0.0)
        {
         double distMinRequerida = InpDistMinEMA_Pips * g_tamanoPip;
         double distCompra = MathAbs(ask - ema1);
         double distVenta  = MathAbs(bid - ema1);

         if(InpCantidadEMAs == CANT_EMA_2)
           {
            distCompra = MathMin(distCompra, MathAbs(ask - ema2));
            distVenta  = MathMin(distVenta,  MathAbs(bid - ema2));
           }

         // Si ni para compra ni para venta alcanza la distancia mínima a la EMA más cercana, salir
         if(distCompra < distMinRequerida && distVenta < distMinRequerida)
            return;
        }
     }

   // 7. Analizar la vela gatillo recién cerrada (índice 1)
   MqlRates vela[1];
   if(CopyRates(_Symbol, g_tfGatillo, 1, 1, vela) < 1)
      return;

   double highVela  = vela[0].high;
   double lowVela   = vela[0].low;
   double openVela  = vela[0].open;
   double closeVela = vela[0].close;

   double rangoVela = highVela - lowVela;
   if(rangoVela <= 0.0)
      return;

   // Validar rango mínimo y máximo de la vela (High - Low)
   double rangoMinPrecio = InpRangoMin_Pips * g_tamanoPip;
   if(rangoVela < rangoMinPrecio)
      return;

   if(InpRangoMax_Pips > 0.0)
     {
      double rangoMaxPrecio = InpRangoMax_Pips * g_tamanoPip;
      if(rangoVela > rangoMaxPrecio)
         return;
     }

   // Validar porcentaje del cuerpo respecto al recorrido total de la vela
   double cuerpoVela       = MathAbs(closeVela - openVela);
   double porcentajeCuerpo = (cuerpoVela / rangoVela) * 100.0;
   if(porcentajeCuerpo < InpPorcentajeCuerpo)
      return;

   bool esVelaAlcista = (closeVela > openVela);
   bool esVelaBajista = (closeVela < openVela);
   if(!esVelaAlcista && !esVelaBajista)
      return;

   // 8. Validar dirección contra operaciones simultáneas y contra la(s) EMA(s)
   bool ejecutarCompra = false;
   bool ejecutarVenta  = false;

   if(esVelaAlcista)
     {
      // Si hay ventas abiertas, no se permite abrir compra en dirección contraria
      if(ventasAbiertas > 0)
         return;

      if(InpModoDireccion == DIRECCION_IGNORAR_EMA)
        {
         ejecutarCompra = true;
        }
      else
        {
         // Verificar distancia mínima para Compra usando Ask hacia la EMA más cercana
         bool cumpleDistancia = true;
         if(InpDistMinEMA_Pips > 0.0)
           {
            double distEMA = MathAbs(ask - ema1);
            if(InpCantidadEMAs == CANT_EMA_2)
               distEMA = MathMin(distEMA, MathAbs(ask - ema2));

            if(distEMA < InpDistMinEMA_Pips * g_tamanoPip)
               cumpleDistancia = false;
           }

         if(cumpleDistancia)
           {
            if(InpModoDireccion == DIRECCION_REVERSION)
              {
               // Reversión: Para compra, toda la vela debe estar por debajo de la(s) EMA(s)
               bool debajoEMA1 = (highVela < ema1);
               bool debajoEMA2 = (InpCantidadEMAs == CANT_EMA_1) ? true : (highVela < ema2);
               if(debajoEMA1 && debajoEMA2)
                  ejecutarCompra = true;
              }
            else if(InpModoDireccion == DIRECCION_A_FAVOR)
              {
               // Tendencial: Para compra, toda la vela debe estar por encima de la(s) EMA(s)
               bool encimaEMA1 = (lowVela > ema1);
               bool encimaEMA2 = (InpCantidadEMAs == CANT_EMA_1) ? true : (lowVela > ema2);
               if(encimaEMA1 && encimaEMA2)
                  ejecutarCompra = true;
              }
           }
        }
     }
   else if(esVelaBajista)
     {
      // Si hay compras abiertas, no se permite abrir venta en dirección contraria
      if(comprasAbiertas > 0)
         return;

      if(InpModoDireccion == DIRECCION_IGNORAR_EMA)
        {
         ejecutarVenta = true;
        }
      else
        {
         // Verificar distancia mínima para Venta usando Bid hacia la EMA más cercana
         bool cumpleDistancia = true;
         if(InpDistMinEMA_Pips > 0.0)
           {
            double distEMA = MathAbs(bid - ema1);
            if(InpCantidadEMAs == CANT_EMA_2)
               distEMA = MathMin(distEMA, MathAbs(bid - ema2));

            if(distEMA < InpDistMinEMA_Pips * g_tamanoPip)
               cumpleDistancia = false;
           }

         if(cumpleDistancia)
           {
            if(InpModoDireccion == DIRECCION_REVERSION)
              {
               // Reversión: Para venta, toda la vela debe estar por encima de la(s) EMA(s)
               bool encimaEMA1 = (lowVela > ema1);
               bool encimaEMA2 = (InpCantidadEMAs == CANT_EMA_1) ? true : (lowVela > ema2);
               if(encimaEMA1 && encimaEMA2)
                  ejecutarVenta = true;
              }
            else if(InpModoDireccion == DIRECCION_A_FAVOR)
              {
               // Tendencial: Para venta, toda la vela debe estar por debajo de la(s) EMA(s)
               bool debajoEMA1 = (highVela < ema1);
               bool debajoEMA2 = (InpCantidadEMAs == CANT_EMA_1) ? true : (highVela < ema2);
               if(debajoEMA1 && debajoEMA2)
                  ejecutarVenta = true;
              }
           }
        }
     }

   // 9. Ejecutar la orden y registrar el riesgo inicial (1R)
   long   stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double distMinSL  = (double)stopsLevel * _Point;

   if(ejecutarCompra)
     {
      double slCompra   = NormalizeDouble(lowVela, _Digits);
      double distanciaR = ask - slCompra;

      if(distanciaR <= 0.0 || distanciaR < distMinSL)
         return;

      double lotes = CalcularLotajePorRiesgo(distanciaR);
      if(lotes <= 0.0)
         return;

      long   puntosR    = (long)MathRound(distanciaR / _Point);
      string comentario = "OMC|R:" + IntegerToString(puntosR);

      if(g_trade.Buy(lotes, _Symbol, ask, slCompra, 0.0, comentario))
        {
         ulong ticketPosicion = g_trade.ResultOrder();
         double precioReal    = g_trade.ResultPrice();
         if(precioReal > 0.0 && precioReal > slCompra)
            distanciaR = precioReal - slCompra;
         GuardarRiesgoPosicion(ticketPosicion, distanciaR);
        }
     }
   else if(ejecutarVenta)
     {
      double slVenta    = NormalizeDouble(highVela, _Digits);
      double distanciaR = slVenta - bid;

      if(distanciaR <= 0.0 || distanciaR < distMinSL)
         return;

      double lotes = CalcularLotajePorRiesgo(distanciaR);
      if(lotes <= 0.0)
         return;

      long   puntosR    = (long)MathRound(distanciaR / _Point);
      string comentario = "OMC|R:" + IntegerToString(puntosR);

      if(g_trade.Sell(lotes, _Symbol, bid, slVenta, 0.0, comentario))
        {
         ulong ticketPosicion = g_trade.ResultOrder();
         double precioReal    = g_trade.ResultPrice();
         if(precioReal > 0.0 && slVenta > precioReal)
            distanciaR = slVenta - precioReal;
         GuardarRiesgoPosicion(ticketPosicion, distanciaR);
        }
     }
  }
//+------------------------------------------------------------------+
