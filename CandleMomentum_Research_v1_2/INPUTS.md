# Inputs V1.2

Todos los inputs y valores por defecto del fuente compilado. Las unidades de riesgo monetario son la moneda de depósito. Un pip EURUSD vale 0.0001; un point y un tick dependen del contrato.

| Input | Tipo | Valor por defecto | Significado |
|---|---|---|---|
| `InpMode` | ENUM_RUN_MODE | `MODE_TRADING` | 0=TRADING; 1=RESEARCH. Research jamás llama a OrderSend. |
| `InpSignalTimeframe` | ENUM_SIGNAL_TF | `SIGNAL_M1` | M1=0, M3=1, M5=2, M15=3, M30=4, H1=5, H2=6, H4=7. Optimizable e independiente del gráfico. |
| `InpMinBodyPercent` | double | `80.0` | Porcentaje mínimo operativo inclusivo, de 0 a 100. No recorta por sí solo el universo Research. |
| `InpRangeFilter` | ENUM_RANGE_FILTER | `RANGE_PIPS` | 0=PIPS, 1=ATR, 2=PIPS_AND_ATR, 3=DISABLED. Determina qué mínimos y máximos se aplican. |
| `InpMinRangePips` | double | `2.0` | Rango mínimo inclusivo en pips; activo en PIPS y combinado. |
| `InpMinRangeATR` | double | `0.8` | Múltiplo mínimo inclusivo del ATR anterior; activo en ATR y combinado. |
| `InpMaxRangePips` | double | `0.0` | Máximo inclusivo en pips; cero desactiva. Solo en PIPS/combinado. |
| `InpMaxRangeATR` | double | `0.0` | Máximo inclusivo en múltiplos ATR; cero desactiva. Solo en ATR/combinado. |
| `InpATRPeriod` | int | `14` | Número de barras del iATR. Entero positivo. Referencia shift 2. |
| `InpATRTimeframe` | ENUM_ATR_TF | `SAME_AS_SIGNAL` | Único valor 0=SAME_AS_SIGNAL. No optimizar otra temporalidad de ATR. |
| `InpRR` | double | `1.0` | Objetivo de precio/riesgo previsto, positivo. TP redondeado al tick más cercano. No limita recorrido Research. |
| `InpRiskPercent` | double | `1.0` | Porcentaje del balance anterior a la operación, >0 y ≤100; no incluye comisiones ni gaps. |
| `InpUseSpreadFilter` | bool | `true` | Activa rechazo comercial por spread; no elimina observación Research. |
| `InpMaxSpreadPips` | double | `1.0` | Máximo inclusivo de spread Ask-Bid en pips. Si vale cero solo permite spread cero; no significa desactivado. |
| `InpAllowSameDirectionPositions` | bool | `true` | Permite nuevas posiciones propias del mismo lado en hedging. El lado opuesto siempre bloquea. |
| `InpMaxConcurrentPositions` | int | `0` | Máximo propio en el símbolo; cero sin límite adicional. En netting 1 permite configuración de una sola posición. |
| `InpMaxAggregateRiskPercent` | double | `0.0` | Máximo de suma de pérdidas previstas al SL de posiciones propias más nueva entrada, sobre balance. Cero desactiva. |
| `InpMagic` | ulong | `120017` | Identificador ulong de órdenes/posiciones propias. Usar uno exclusivo por instancia y símbolo. |
| `InpDeviationPoints` | int | `10` | Desviación de ejecución solicitada en POINTS, no pips. Entero no negativo; su aplicación depende del modo del broker. |
| `InpResearchMaxBars` | int | `50` | Número positivo de barras existentes de observación. Edad 0 a N-1, vencimiento al inicio de edad N. |
| `InpResearchMinBodyPercent` | double | `0.0` | Recorte opcional del universo Research, 0 a 100%; cero desactiva. Los dojis se excluyen siempre. |
| `InpMinTradesForScore` | int | `50` | Mínimo positivo de trades requerido por OnTester; menos operaciones reciben score desfavorable. |
| `InpEnableTelemetry` | bool | `true` | Activa CSV y acumulación de agregados; false conserva decisiones y no exporta. Comprobar paridad en tester. |
| `InpRunLabel` | string | `"CMR"` | Etiqueta del RunID. Usar letras, números, guiones y guion bajo; no rutas. |
| `InpServerTimezone` | string | `"UNKNOWN"` | Zona horaria de servidor documentada por el usuario; UNKNOWN por defecto. No convierte los timestamps. |
| `InpSummaryPipBinWidth` | double | `2.0` | Ancho positivo en pips de intervalos del resumen. Adaptar al timeframe; no afecta señales. |
