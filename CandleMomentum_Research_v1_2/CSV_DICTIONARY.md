# Diccionario CSV V1.2

Claves relacionales: RunID + SignalID. Valores booleanos: 1/0. Los valores faltantes se dejan vacíos; no se interpretan como cero. Precios en unidades de cotización, pips EURUSD=0.0001. El riesgo/costes monetarios están en moneda de depósito. Timestamps de servidor, no hora local.

## RunMetadata.csv

| Columna | Definición |
|---|---|
| `RunID` | Identificador único de corrida/carpeta; clave de unión entre archivos. |
| `Key` | Nombre del metadato, una fila por clave. |
| `Value` | Valor textual del metadato, unidades según clave; inputs documentados en INPUTS.md. |

## ResearchSignals.csv

| Columna | Definición |
|---|---|
| `RunID` | Identificador único de corrida/carpeta; clave de unión entre archivos. |
| `SignalID` | Símbolo_TF_timestampDireccional_dirección; estable entre corridas. |
| `Timeframe` | Nombre ENUM_TIMEFRAMES de la señal. |
| `SignalTime` | Fecha y hora de apertura de vela gatillo, reloj de servidor, texto YYYY.MM.DD HH:MM:SS. |
| `SignalTimestamp` | Misma apertura como datetime MQL5 en segundos; no asumir UTC real. |
| `Direction` | BUY o SELL según Close frente a Open. |
| `Open` | Apertura original de vela gatillo, precio. |
| `High` | Máximo original, precio. |
| `Low` | Mínimo original, precio. |
| `Close` | Cierre original, precio. |
| `RangePips` | (High−Low)/0.0001. |
| `BodyPips` | abs(Close−Open)/0.0001. |
| `BodyPercent` | 100*BodyPips/RangePips. |
| `UpperWickPips` | (High−max(Open,Close))/0.0001. |
| `LowerWickPips` | (min(Open,Close)−Low)/0.0001. |
| `ATRReference` | iATR de shift 2 en precio; vacío si falta. |
| `ATRPips` | ATRReference/0.0001; vacío si falta. |
| `RangeATR` | RangePips/ATRPips, adimensional; vacío si falta. |
| `ATRValid` | 1 si referencia confirmada, positiva y finita; 0 en otro caso. |
| `EntryTimeMsc` | Timestamp de cotización de entrada virtual/prevista o primer fill real en Trades, milisegundos de servidor. |
| `EntryBar` | Apertura de barra de entrada, segundos de servidor. |
| `SpreadPips` | (Ask−Bid)/0.0001 en cotización de señal; ya incorporado en precios. |
| `ExpectedEntry` | Ask BUY o Bid SELL previo al envío / entrada virtual, precio. |
| `SL` | Extremo original de gatillo, sin buffer, precio. |
| `TP` | Objetivo previsto redondeado a tick, precio. Cero si R no válido. |
| `ExpectedRiskPips` | side*(ExpectedEntry−SL)/0.0001. Puede ser ≤0 solo en observaciones no ejecutables. |
| `BodyPass` | 1 si cumple porcentaje mínimo operativo. |
| `PipsPass` | 1 si cumple mínimo y máximo configurados de pips, calculado aunque filtro inactivo. |
| `ATRPass` | 1 si ATR válido y cumple mínimo/máximo ATR, calculado aunque filtro inactivo. |
| `CombinedPass` | 1 si cuerpo y filtros activos de rango pasan; no incluye spread ni restricciones de cuenta. |
| `PathValid` | 1 si R virtual es estrictamente positivo; independiente de ejecución comercial. |
| `CommercialExecutable` | 1 si preflight comercial pasa; en Signals se vuelve 0 ante rechazo del envío. No garantiza fill. En Research no se envía. |
| `RejectReason` | Motivos separados por |; vacío si pasa. Ver catálogo al final. |
| `RequestedRiskMoney` | Balance antes de entrada * RiskPercent/100, moneda de depósito. |
| `ExpectedLots` | Volumen previsto redondeado hacia abajo, lotes. Cero si no se pudo calcular. |
| `MFE_Pips` | Máxima excursión favorable observada no negativa, pips. |
| `MAE_Pips` | Máxima excursión adversa observada no negativa, pips. |
| `MFE_R` | MFE precio/R de entrada; vacío si R inválido. |
| `MAE_R` | MAE precio/R de entrada; vacío si R inválido. |
| `MFE_TimeMsc` | Primer timestamp del máximo favorable registrado; 0 si nunca hubo excursión positiva. |
| `MAE_TimeMsc` | Primer timestamp del máximo adverso registrado; 0 si nunca hubo excursión adversa positiva. |
| `EndReason` | STOP, NOT_EXECUTABLE o censura CENSORED_HORIZON/TEST_END/DEINIT/DATA_GAP. |
| `EndTimeMsc` | Timestamp del evento que termina observación. El tick de horizonte no se incluye en extremos. |

## ResearchLevels.csv

| Columna | Definición |
|---|---|
| `RunID` | Identificador único de corrida/carpeta; clave de unión entre archivos. |
| `SignalID` | Símbolo_TF_timestampDireccional_dirección; estable entre corridas. |
| `TargetR` | Umbral favorable: 0.5, 1, 1.5, 2, 3, 4 o 5. |
| `Outcome` | TARGET_BEFORE_SL, SL_BEFORE_TARGET, NOT_EXECUTABLE o clase de censura; excluyentes por observación y objetivo. |
| `ArrivalTimeMsc` | Primera llegada al objetivo o al SL que resuelve ese objetivo. Vacío si censurado/inválido. |
| `ObservationEndTimeMsc` | Final global de observación, distinto de llegada a un nivel previo. |

## ResearchSummary.csv

| Columna | Definición |
|---|---|
| `RunID` | Identificador único de corrida/carpeta; clave de unión entre archivos. |
| `Dimension` | ALL, TIMEFRAME, BODY, RANGE_ATR, RANGE_PIPS, DIRECTION o SERVER_HOUR. |
| `Group` | Clave del grupo; intervalos no solapados dentro de dimensión; MISSING para ATR ausente. |
| `Total` | Observaciones del grupo, incluidas las no ejecutables por R inválido. |
| `Valid` | Observaciones con PathValid=1; no exige CommercialExecutable. |
| `CensoredObservations` | Observaciones cuyo final global es una censura, aunque algunos objetivos estén resueltos. |
| `TargetR` | Umbral favorable: 0.5, 1, 1.5, 2, 3, 4 o 5. |
| `Hits` | Objetivos alcanzados antes del SL. |
| `Stops` | SL alcanzado antes del objetivo. |
| `CensoredForTarget` | Trayectorias válidas sin resolución de este objetivo; ninguna cuenta como stop. |
| `Resolved` | Hits+Stops. |
| `HitPctResolved` | 100*Hits/Resolved; vacío si denominador cero. |
| `HitPctAllValid` | 100*Hits/Valid; vacío si cero. Fracción observada, no asume pérdida de censurados. |
| `MeanMFE_R` | Media MFE_R válida incluyendo recorridos truncados. |
| `MedianMFE_R` | Mediana exacta MFE_R válida, incluyendo recorridos truncados. |
| `MeanMAE_R` | Media MAE_R válida. |
| `MedianMAE_R` | Mediana exacta MAE_R válida. |
| `MeanMFE_Pips` | Media MFE en pips de trayectorias válidas. |
| `MedianMFE_Pips` | Mediana exacta MFE en pips válida. |
| `MeanMAE_Pips` | Media MAE en pips válida. |
| `MedianMAE_Pips` | Mediana exacta MAE en pips válida. |
| `MeanSL_Pips` | Media de distancia virtual de entrada a SL de trayectorias válidas. |

## Signals.csv

| Columna | Definición |
|---|---|
| `RunID` | Identificador único de corrida/carpeta; clave de unión entre archivos. |
| `SignalID` | Símbolo_TF_timestampDireccional_dirección; estable entre corridas. |
| `Timeframe` | Nombre ENUM_TIMEFRAMES de la señal. |
| `SignalTime` | Fecha y hora de apertura de vela gatillo, reloj de servidor, texto YYYY.MM.DD HH:MM:SS. |
| `SignalTimestamp` | Misma apertura como datetime MQL5 en segundos; no asumir UTC real. |
| `Direction` | BUY o SELL según Close frente a Open. |
| `Open` | Apertura original de vela gatillo, precio. |
| `High` | Máximo original, precio. |
| `Low` | Mínimo original, precio. |
| `Close` | Cierre original, precio. |
| `RangePips` | (High−Low)/0.0001. |
| `BodyPips` | abs(Close−Open)/0.0001. |
| `BodyPercent` | 100*BodyPips/RangePips. |
| `UpperWickPips` | (High−max(Open,Close))/0.0001. |
| `LowerWickPips` | (min(Open,Close)−Low)/0.0001. |
| `ATRReference` | iATR de shift 2 en precio; vacío si falta. |
| `ATRPips` | ATRReference/0.0001; vacío si falta. |
| `RangeATR` | RangePips/ATRPips, adimensional; vacío si falta. |
| `ATRValid` | 1 si referencia confirmada, positiva y finita; 0 en otro caso. |
| `EntryTimeMsc` | Timestamp de cotización de entrada virtual/prevista o primer fill real en Trades, milisegundos de servidor. |
| `EntryBar` | Apertura de barra de entrada, segundos de servidor. |
| `SpreadPips` | (Ask−Bid)/0.0001 en cotización de señal; ya incorporado en precios. |
| `ExpectedEntry` | Ask BUY o Bid SELL previo al envío / entrada virtual, precio. |
| `SL` | Extremo original de gatillo, sin buffer, precio. |
| `TP` | Objetivo previsto redondeado a tick, precio. Cero si R no válido. |
| `ExpectedRiskPips` | side*(ExpectedEntry−SL)/0.0001. Puede ser ≤0 solo en observaciones no ejecutables. |
| `BodyPass` | 1 si cumple porcentaje mínimo operativo. |
| `PipsPass` | 1 si cumple mínimo y máximo configurados de pips, calculado aunque filtro inactivo. |
| `ATRPass` | 1 si ATR válido y cumple mínimo/máximo ATR, calculado aunque filtro inactivo. |
| `CombinedPass` | 1 si cuerpo y filtros activos de rango pasan; no incluye spread ni restricciones de cuenta. |
| `PathValid` | 1 si R virtual es estrictamente positivo; independiente de ejecución comercial. |
| `CommercialExecutable` | 1 si preflight comercial pasa; en Signals se vuelve 0 ante rechazo del envío. No garantiza fill. En Research no se envía. |
| `RejectReason` | Motivos separados por |; vacío si pasa. Ver catálogo al final. |
| `RequestedRiskMoney` | Balance antes de entrada * RiskPercent/100, moneda de depósito. |
| `ExpectedLots` | Volumen previsto redondeado hacia abajo, lotes. Cero si no se pudo calcular. |

## Trades.csv

| Columna | Definición |
|---|---|
| `RunID` | Identificador único de corrida/carpeta; clave de unión entre archivos. |
| `SignalID` | Símbolo_TF_timestampDireccional_dirección; estable entre corridas. |
| `PositionID` | POSITION_IDENTIFIER estable para asociar todo el historial. |
| `PositionTicket` | Último ticket observado de posición; puede quedar 0 si abrió/cerró antes de poder seleccionarla. |
| `OrderTickets` | Tickets únicos de órdenes de entrada/salida separados por |. |
| `DealTickets` | Todos los deals BUY/SELL de la posición, separados por |; incluye fills parciales. |
| `EntryTimeMsc` | Timestamp de cotización de entrada virtual/prevista o primer fill real en Trades, milisegundos de servidor. |
| `ExitTimeMsc` | Timestamp del último fill de salida. |
| `Direction` | BUY o SELL según Close frente a Open. |
| `Timeframe` | Nombre ENUM_TIMEFRAMES de la señal. |
| `ExpectedEntry` | Ask BUY o Bid SELL previo al envío / entrada virtual, precio. |
| `ActualEntry` | Precio medio ponderado por volumen de fills de entrada. |
| `ActualExit` | Precio medio ponderado por volumen de todos los fills de salida. |
| `SL` | Extremo original de gatillo, sin buffer, precio. |
| `TP` | Objetivo previsto redondeado a tick, precio. Cero si R no válido. |
| `ExpectedRR` | InpRR solicitado antes de redondear TP. |
| `EffectiveRR` | side*(TP−ActualEntry)/(side*(ActualEntry−SL)); 0 si riesgo efectivo de precio inválido. |
| `ExpectedLots` | Volumen previsto redondeado hacia abajo, lotes. Cero si no se pudo calcular. |
| `ExecutedLots` | Suma de volúmenes de entrada efectivamente ejecutados. |
| `RequestedRiskMoney` | Balance antes de entrada * RiskPercent/100, moneda de depósito. |
| `ExpectedRiskPips` | side*(ExpectedEntry−SL)/0.0001. Puede ser ≤0 solo en observaciones no ejecutables. |
| `EffectiveRiskPips` | side*(ActualEntry−SL)/0.0001. |
| `EffectiveRiskMoney` | Suma de pérdidas positivas calculadas de fills de entrada a SL con OrderCalcProfit; moneda de cuenta, conversión disponible al descubrir cada fill por primera vez; queda congelada. |
| `SpreadPips` | (Ask−Bid)/0.0001 en cotización de señal; ya incorporado en precios. |
| `EntryCommission` | Suma con signo de DEAL_COMMISSION de entradas. |
| `ExitCommission` | Suma con signo de DEAL_COMMISSION de salidas. |
| `TotalCommission` | EntryCommission+ExitCommission, sin invertir signo. |
| `Swap` | Suma con signo de DEAL_SWAP de la posición. |
| `Fees` | Suma con signo de DEAL_FEE. |
| `GrossProfit` | Suma de DEAL_PROFIT, excluye comisión/swap/fees separados. |
| `NetProfit` | GrossProfit+TotalCommission+Swap+Fees; no se resta nuevamente spread. |
| `NetR` | NetProfit/EffectiveRiskMoney; vacío si riesgo cero. |
| `MFE_Pips` | Máxima excursión favorable observada no negativa, pips. |
| `MAE_Pips` | Máxima excursión adversa observada no negativa, pips. |
| `MFE_R` | MFE precio/R de entrada; vacío si R inválido. |
| `MAE_R` | MAE precio/R de entrada; vacío si R inválido. |
| `MFE_TimeMsc` | Primer timestamp del máximo favorable registrado; 0 si nunca hubo excursión positiva. |
| `MAE_TimeMsc` | Primer timestamp del máximo adverso registrado; 0 si nunca hubo excursión adversa positiva. |
| `DurationSeconds` | (último fill salida−primer fill entrada)/1000. |
| `ExitReason` | Razones DEAL_REASON de salidas, separadas por |. Identifica SL/TP y eventos externos. |
| `EntrySlippagePips` | side*(ActualEntry−ExpectedEntry)/0.0001; positivo es peor entrada. |
| `HistoryAnomaly` | 1 si hubo reversión inesperada o fallo de cálculo de riesgo del historial. |

## ExecutionEvents.csv

| Columna | Definición |
|---|---|
| `RunID` | Identificador único de corrida/carpeta; clave de unión entre archivos. |
| `ObservedTimeMsc` | Último tick válido procesado al recibir evento; no necesariamente el timestamp original del servidor de ese evento. |
| `Event` | Tipo de transacción o evento propio SEND_RESULT, REQUEST, ORDER_NO_FILL, POSITION_COMPLETE, UNFINISHED_AT_END. |
| `SignalID` | Símbolo_TF_timestampDireccional_dirección; estable entre corridas. |
| `OrderTicket` | Ticket de orden del evento o cero. |
| `DealTicket` | Ticket de deal del evento o cero. |
| `PositionIDOrTicket` | En eventos propios: identificador estable; en eventos de transacción: ticket trans.position. Interpretar junto con Event. |
| `Retcode` | Código comercial, cero en eventos sin respuesta comercial. |
| `Detail` | Comentario del servidor, motivo o precio de transacción; texto diagnóstico. |

## Claves RunMetadata

Todas las claves exportadas (los inputs se detallan en INPUTS.md):

`Version`, `Mode`, `Symbol`, `Timeframe`, `FirstTickMsc`, `LastTickMsc`, `FirstObservedServerTime`, `LastObservedServerTime`, `TicksProcessed`, `InvalidTicks`, `SkippedBars`, `DataFailures`, `InitialBalance`, `Currency`, `Leverage`, `Server`, `ServerTimezone`, `AccountMarginMode`, `Point`, `Pip`, `TickSize`, `Digits`, `TickValueProfit`, `TickValueLoss`, `ContractSize`, `VolumeMin`, `VolumeMax`, `VolumeStep`, `VolumeLimit`, `StopsLevelPoints`, `FreezeLevelPoints`, `FloatingSpread`, `Candidates`, `Signals`, `BodyPassCount`, `PipsPassCount`, `ATRPassCount`, `CombinedPassCount`, `Trades`, `Observations`, `CensoredObservations`, `UnfinishedTradeRequests`, `SignalSequenceFNV1a64`, `EndReason`, `IOFailure`, `TickCoverage`, `InpMode`, `InpSignalTimeframe`, `InpMinBodyPercent`, `InpRangeFilter`, `InpMinRangePips`, `InpMinRangeATR`, `InpMaxRangePips`, `InpMaxRangeATR`, `InpATRPeriod`, `InpATRTimeframe`, `InpRR`, `InpRiskPercent`, `InpUseSpreadFilter`, `InpMaxSpreadPips`, `InpAllowSameDirectionPositions`, `InpMaxConcurrentPositions`, `InpMaxAggregateRiskPercent`, `InpMagic`, `InpDeviationPoints`, `InpResearchMaxBars`, `InpResearchMinBodyPercent`, `InpMinTradesForScore`, `InpEnableTelemetry`, `InpRunLabel`, `InpServerTimezone`, `InpSummaryPipBinWidth`.

First/LastObservedServerTime son los extremos observados, no las fechas solicitadas al tester. TicksProcessed cuenta llamadas válidas de OnTick, no ticks garantizados del histórico. SkippedBars cuenta omisiones detectadas de transición; DataFailures cuenta fallos de serie. Candidates incluye todas las velas direccionales leídas; Signals/CombinedPassCount y la firma incluyen las que pasan filtros operativos, antes del recorte opcional del universo Research. Los demás PassCount son evaluaciones individuales, aunque el filtro no esté activo. Trades cuenta posiciones completas exportables, no deals. Los datos contractuales se consultan al finalizar; no reconstruyen cambios históricos de especificación. UnfinishedTradeRequests requiere inspección de ExecutionEvents. InitialBalance es el balance leído en OnInit. EndReason identifica TEST_END o DEINIT_n. IOFailure=1 invalida integridad; TickCoverage declara el alcance OnTick.

## Motivos comerciales

`FILTERS`: no cumple selección operativa. `ATR_UNAVAILABLE`: falta referencia requerida. `SL_WRONG_SIDE`: riesgo no positivo. `SPREAD`: supera máximo. `SL_OFF_TICK_GRID`: extremo no representable. `STOPS_LEVEL`: distancias SL/TP inválidas. `SYMBOL_TRADE_MODE`/`ORDER_MODE`: contrato no permite la operación. `NETTING_CONFIGURATION`: configuración simultánea incompatible. `NETTING_FOREIGN_POSITION`: posición ajena impediría independencia. `OPPOSITE_POSITION`/`SAME_DIRECTION_POSITION`/`POSITION_LIMIT`: restricción de posiciones propias. `REQUEST_UNSETTLED`: solicitud previa aún pendiente de resolver. `RISK_CALCULATION`: OrderCalcProfit no permite medir pérdida. `VOLUME_BELOW_MINIMUM`: volumen flooreado insuficiente. `RISK_ROUNDING`: excedería presupuesto por redondeo. `AGGREGATE_RISK`: límite agregado o riesgo existente desconocido. `MARGIN`: cálculo fallido o margen insuficiente. `FILL_POLICY`: no hay FOK/IOC. `ORDERCHECK_codigo_texto`: rechazo del preflight. `SEND_codigo`: rechazo del envío.

## Salidas auxiliares Python

- Distributions: Field=variable, Quantile=probabilidad 0..1, Value=cuantil empírico nearest-rank, Count=número de valores válidos. En trading la distribución es condicional a señales aceptadas; usar Research para el universo completo.
- EquivalentRuns: Group=clase de equivalencia contextual, RunID=ejecución, EquivalentRuns=conteo, DistinctConfigurations=configuraciones completas distintas, SelectionSHA256=firma IDs, Trades=operaciones completas.
- ParameterSelections: Parameter=input, Value=valor, DistinctSelections=número de SHA distintos observados con ese valor; no es un efecto causal aislado.
- TickReplayAudit: SignalID, MFE_Pips/MAE_Pips recalculados, Differences=campos diferentes separados por barra vertical, Coverage=INTERVAL_PRESENT/TICK_EXPORT_END/MISSING, EntryTimestampAmbiguous=entrada no única en mismo milisegundo, HistoricalTicks=ticks usados hasta stop/final. INTERVAL_PRESENT solo verifica cobertura temporal de extremos; no garantiza ausencia de huecos interiores.
- Exportador de ticks: TimeMsc=timestamp servidor, Bid/Ask=precios, Flags=banderas MqlTick originales.
