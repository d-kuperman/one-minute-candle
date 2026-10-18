# CandleMomentum Research V1.2

Expert Advisor MQL5 escrito desde cero. EURUSD, incluidos sufijos cuyo contrato tenga EUR como moneda base y USD como moneda de beneficio. No contiene EMA, filtros horarios, trailing, órdenes pendientes ni componentes de otras estrategias.

**Estado de validación:** consultar `validation/ESTADO.md`. Compilar no equivale a verificar operaciones en el Strategy Tester. Esta entrega no afirma rentabilidad ni equivalencia exacta con un EA anterior. No se realizó optimización.

## Archivos

- `CandleMomentum_Research_v1_2.mq5` y `.ex5`: EA autocontenido y compilado.
- `presets/Original_Pips.set`, `RangeATR.set`, `Research.set`: parámetros completos.
- `INPUTS.md`: todos los parámetros y sus unidades.
- `CSV_DICTIONARY.md`: diccionario de columnas y metadatos.
- `tests/CMR_UnitTests.mq5`: script de pruebas que invoca las funciones del EA con datos sintéticos; nunca llama a la función que envía órdenes.
- `tools/analyze.py`: integridad de CSV, cuantiles y detección de selecciones equivalentes.
- `tools/ExportTicksForAudit.mq5`, `tools/replay_ticks.py`: exportación de ticks y contraste retrospectivo del recorrido virtual.
- `TEST_PLAN.md`: matriz de las 30 validaciones pedidas y criterios de aceptación.
- `examples/SYNTHETIC_RESEARCH/`: dos trayectorias inventadas y verificadas; ejemplo de lectura y replay, no datos de mercado ni backtest.

## Instalar y ejecutar

1. En MT5: Archivo → Abrir carpeta de datos. Copiar el `.mq5` y `.ex5` a `MQL5/Experts/CandleMomentum_Research_v1_2/`. No requiere includes ni librerías externas.
2. Abrir el fuente con MetaEditor y compilar con F7 si se desea regenerar el binario. Actualizar el Navegador de MT5.
3. Abrir Strategy Tester, seleccionar el EA y EURUSD. Usar **Cada tick basado en ticks reales**. Registrar el servidor, fechas, depósito, apalancamiento y disponibilidad/calidad del histórico.
4. Seleccionar un período de prueba y cargar uno de los `.set` en Entradas. La temporalidad de señal es `InpSignalTimeframe`, independiente del período visual del gráfico/tester.
5. Ejecutar una prueba individual, sin optimización, y revisar Journal. El EA imprime la carpeta de resultados. No envía solicitudes comerciales en `MODE_RESEARCH`.
6. Copiar la carpeta RunID completa para analizarla. Con agentes locales, está en el sandbox `Tester/Agent-.../MQL5/Files/CandleMomentum_Research_v1_2/<RunID>/`; en ejecución normal, `MQL5/Files/...`. Las rutas dependen del terminal/agente. No usa `FILE_COMMON`.

Los CSV son UTF-8, separador coma, punto decimal, comillas escapadas y encabezados estables. Usar **Datos → Desde texto/CSV** al abrirlos en un Excel configurado con coma decimal. No modificar manualmente separadores para analizarlos con Python.

### MODE_TRADING

Cargar `Original_Pips.set`: M1, cuerpo ≥80%, rango ≥2 pips, RR=1, riesgo 1% sobre balance, spread ≤1 pip, entradas simultáneas de igual dirección. Esta configuración **requiere hedging**. No abrirá una compra mientras haya una venta propia ni viceversa. Magic identifica las posiciones propias en el símbolo.

En netting, desactivar `InpAllowSameDirectionPositions` o fijar `InpMaxConcurrentPositions=1`. En ambos casos, no agrega exposición a una posición existente. Rechaza una posición ajena en el mismo símbolo para evitar mezclarla. La configuración simultánea incompatible falla en inicialización con un mensaje claro.

Las señales se consumen una vez: no se reintentan por spread, margen, datos faltantes, SL inválido ni errores de ejecución. Al adjuntar/reiniciar, la primera barra observada solo establece la referencia; se espera la siguiente transición. Después de perder la serie o saltarse varias barras, no ejecuta las señales pendientes.

El SL conserva el extremo exacto; si no pertenece a la rejilla de ticks o incumple restricciones, se rechaza. El TP se redondea al tick más próximo y se vuelve a validar. Se registra el RR efectivo usando entrada real y TP colocado. No reajusta SL/TP después de la ejecución. No cierra por señal contraria ni por vencimiento del horizonte de investigación.

Se prefieren FOK y después IOC; no se usa RETURN para evitar residuos pendientes. `OrderCheck` y retcodes aportan validación adicional a las especificaciones locales. Una respuesta aceptada aún no equivale a una posición completamente ejecutada: el historial resuelve los fills.

### MODE_RESEARCH

Cargar `Research.set`. Incluye todas las velas direccionales válidas; el mínimo del universo vale cero. El filtro operativo se calcula y registra, pero no elimina observaciones. Un ATR ausente queda vacío con `ATRValid=0`, no como ATR cero. La referencia siempre es shift 2, mientras la gatillo es shift 1.

Cada observación es independiente. Su BUY entra al Ask y se evalúa al Bid; SELL entra al Bid y se evalúa al Ask. El spread inicial produce MAE cuando corresponde. Si el SL está del lado incorrecto, se exporta `NOT_EXECUTABLE` y no se calculan cocientes R. Los demás rechazos comerciales no impiden estudiar una trayectoria matemáticamente válida.

`CommercialExecutable` es una comprobación de la cotización, filtros, contrato, riesgo, margen y **cuenta real/simulada actual** mediante `OrderCheck`, sin `OrderSend`. Las observaciones virtuales no ocupan capacidad de cartera. Por ello no significa que una cartera pueda ejecutar todas simultáneamente, ni garantiza aceptación futura del servidor.

Los niveles son 0.5, 1, 1.5, 2, 3, 4 y 5R. Cada uno conserva su primera llegada. Un tick puede alcanzar varios objetivos a la vez. Una observación sigue viva después de alcanzar 1R o incluso 5R, hasta SL u horizonte. En un gap al stop, MAE refleja la cotización observada más allá del SL; no se fuerza artificialmente a 1R.

El horizonte cuenta barras **existentes** de la temporalidad, desde la barra de entrada. Con 50, se incluyen las barras de edad 0 a 49; la primera cotización de la barra 50 vence la observación antes de medirla. Los fines de semana sin barras no cuentan como barras sintéticas. `CENSORED_TEST_END` indica fin de prueba; `CENSORED_DEINIT` una interrupción; `CENSORED_DATA_GAP` una pérdida de referencias de serie. Un nivel alcanzado previamente sigue resuelto aunque la observación termine censurada.

## Analizar los resultados

Python 3.10 o posterior, sin paquetes externos:

```powershell
python tools/analyze.py "C:\ruta\RunID"
python tools/analyze.py "C:\ruta\RunA" "C:\ruta\RunB" --equivalence "EquivalentRuns.csv"
```

Genera `Analysis.json` y `Distributions.csv` dentro de cada run, más `EquivalentRuns.csv` y `ParameterSelections.csv` en la ubicación elegida. Una aserción fallida detiene el análisis: no se ocultan CSV incompletos, duplicados, niveles no monótonos ni sumas netas incoherentes.

`ResearchSummary.csv` se genera en el EA al finalizar. Incluye agregaciones marginales por timeframe, cuerpo, RangeATR, rango en pips, dirección y hora de servidor, además de ALL. Los intervalos son cerrados por izquierda y abiertos por derecha, salvo cuerpo 95–100 que incluye 100; RangeATR ≥3 pertenece a `[3,inf)`. No son grupos mutuamente excluyentes entre dimensiones: no sumar ALL con BODY, etc. Para cruces multidimensionales o análisis de las señales que acaban en stop, unir `ResearchSignals` y `ResearchLevels` por RunID+SignalID.

Medianas exactas y medias de MFE/MAE se calculan sobre trayectorias válidas, incluyendo las truncadas/censuradas, con el conteo de censura visible. Son excursiones **observadas**, no estimadores de la excursión final no censurada. La memoria de las medianas crece linealmente con las observaciones exportadas; a varios millones de señales conviene particionar por períodos y reagrupar los CSV, sin promediar medianas parciales.

Ejemplo conceptual: 100 trayectorias válidas, 40 llegan a 1R, 35 tocan SL antes de 1R y 25 quedan censuradas para 1R. `HitPctResolved = 40/75*100 = 53.3333%`; `HitPctAllValid = 40/100*100 = 40%`. Ninguna cifra transforma las 25 censuradas en pérdidas. Una observación puede contar como censurada globalmente y ya estar resuelta para 0.5R y 1R.

No sumar retornos virtuales para inventar un balance. Los grupos con pocas observaciones y la dependencia entre ventanas superpuestas deben tratarse explícitamente al inferir incertidumbre; una tasa descriptiva no demuestra ventaja operativa. Las comparaciones entre temporalidades requieren ejecuciones separadas con el mismo período y fuente.

### Diseñar una búsqueda ATR sin optimizar durante el desarrollo

Primero ejecutar Research sin recortar cuerpo y revisar cuantiles de `RangeATR`, `RangePips` y `BodyPercent`. Luego preparar una malla gruesa (por ejemplo 0.5, 0.75, 1, 1.25, 1.5, 2 y 3 ATR, solo si la distribución observada la justifica). Separar períodos de exploración y validación y exigir suficientes operaciones en cada uno.

En la pestaña de optimización, activar solo parámetros que afectan al modo elegido:

| Filtro | Optimizar umbrales |
|---|---|
| PIPS | Mínimo/máximo en pips; no ATR |
| ATR | Mínimo/máximo ATR, período ATR; no pips |
| PIPS_AND_ATR | Ambos conjuntos |
| DISABLED | Ningún umbral de rango |

No optimizar máximo de spread si su filtro está apagado; ni parámetros monetarios/RR para buscar una rentabilidad virtual en Research. MT5 no impide automáticamente todos los pases redundantes. En Research, RR y riesgo solo modifican la evaluación comercial, no la trayectoria R ni los niveles estadísticos.

La firma FNV-1a de 64 bits concatena identificadores estables de señales aceptadas (símbolo, timeframe, timestamp de vela, dirección), separados por salto de línea, en orden cronológico. No usa beneficios. El analizador añade SHA-256 de IDs ordenados y solo agrupa runs con igual modo/símbolo/TF/ventana/universo y ambas firmas iguales. Una selección equivalente no implica iguales fills ni resultados comerciales. Comparar fuentes de datos idénticas; las firmas no prueban que OHLC o ticks sean idénticos. `ParameterSelections.csv` es un resumen descriptivo de valores y selecciones observados, no atribución causal del efecto aislado de un parámetro cuando cambian varios a la vez.

### Score operativo

Sea n el número de trades del tester, N=`InpMinTradesForScore`, P el beneficio neto del tester y D el drawdown monetario máximo de equity:

- Research devuelve −1,000,000,000.
- Si n<N, devuelve −1,000,000+n/N.
- En otro caso: `P/max(1,D) * min(1,n/(2*N))`, limitado a [−999999,999999].
- Un resultado no finito devuelve −1,000,000,000.

No utiliza Profit Factor ni divide por pérdidas nulas. La escala monetaria mínima 1 evita divisiones por cero. El criterio es para ordenar pruebas, no una medida de significación ni una garantía de estabilidad fuera de muestra.

## Arquitectura y contratos de funciones

| Funciones | Responsabilidad |
|---|---|
| OnInit, InitCSV | Validar contrato/inputs/cuenta, crear ATR y archivos únicos; rechazar estado propio anterior no recuperable |
| OnTick, ReadSignal | Detectar una transición de TF, consumir la señal sin reintentos; CopyRates shift 1 y CopyBuffer shift 2 |
| MakeSignal | Transformar OHLC, ATR y cotización en características, filtros, entrada, SL, R y TP; sin órdenes |
| ValidateCommercial, DirectionVolume, FloorVolume | Riesgo en moneda de depósito con OrderCalcProfit, restricciones de volumen/cartera y margen con OrderCalcMargin |
| BuildRequest, Preflight, SendSignal | Solicitud de mercado protegida, OrderCheck, envío único y retcode |
| OnTradeTransaction, OnTrade, ReconcileTrades | Asociar order/deal/POSITION_IDENTIFIER; reconstruir historial para no duplicar comisiones o cierres parciales |
| TrackTick, TradeQuote | Extremos ejecutables mientras existe la posición; incorporar precios de salidas parciales/finales y gaps |
| StartObservation, ExpireResearch, ResearchTick | Observaciones independientes, vencimiento por barras, primera llegada por ticks |
| Observe, FinishObservation | MFE/MAE no negativos y cierre estadístico con siete resultados excluyentes |
| Aggregate, GroupAdd, Summary, Median | Contadores por dimensión, censura por objetivo, medias y medianas exactas |
| SignalRow, ExcursionRow, Write, Event, Metadata | Serialización estable, eventos y trazabilidad de corrida |
| Finish, OnTester, OnDeinit | Finalización idempotente, censura final, flush y liberación de recursos; score solo operativo |

La reconciliación agrupa por POSITION_IDENTIFIER, no por cada deal. Suma comisión de entrada/salida, swap y DEAL_FEE; el neto es bruto+comisiones+swap+fees, sin restar spread nuevamente. El precio de entrada y salida es promedio ponderado por volumen. El riesgo monetario efectivo suma el riesgo de los fills de entrada frente al SL inicial. MFE/MAE de una entrada con fills parciales usan como referencia final ese promedio ponderado y las cotizaciones observadas desde el primer fill; no describen una curva de P&L monetario de exposición variable. `HistoryAnomaly=1` exige investigar una conversión de riesgo fallida o una reversión inesperada.

El riesgo monetario de cada fill se calcula al descubrirlo por primera vez y se conserva al cerrar. Si la moneda de depósito requiere conversión, no se dispone de una reconstrucción independiente del tipo de conversión exacto del instante de ejecución; se usa el disponible en esa primera reconciliación. La enumeración de temporalidades usa valores consecutivos 0–7 para que una optimización no recorra los huecos numéricos de ENUM_TIMEFRAMES.

## Limitaciones y auditoría

- OnTick puede omitir eventos cuando ya hay otro NewTick pendiente; no se afirma cobertura completa. No sustituye ticks por High/Low. `TickCoverage=ONTICK_ONLY_NOT_VERIFIED` hace visible la limitación. La documentación oficial lo especifica en [OnTick](https://www.mql5.com/en/docs/event_handlers/ontick).
- Para auditar: instalar `ExportTicksForAudit.mq5` en Scripts, compilarlo y ejecutarlo sobre EURUSD con el mismo servidor y un intervalo que cubra las observaciones, incluidos sus finales. Requiere sincronización del histórico. Si informa chunk incompleto, volver a exportar tras cargar datos. No aceptar un archivo parcial como evidencia completa.
- Ejecutar `python tools/replay_ticks.py RUN TICKS.csv`. Contrasta MFE/MAE y resultados de niveles. Muestra diferencias, falta de cobertura y ambigüedad de entrada en milisegundos iguales; no certifica por sí solo la procedencia real de los ticks ni reconstruye el orden de eventos del broker. Para trading, contrastar también los ticks dentro del intervalo de cada posición y los precios de deals; el replayer incluido cubre Research.
- Los tiempos son de servidor. No se infiere UTC−3 del equipo ni se calcula históricamente DST. `InpServerTimezone` permite documentar una zona conocida; UNKNOWN es el valor honesto por defecto.
- OrderCalcProfit devuelve moneda de la cuenta, no necesariamente USD. El riesgo de precio excluye comisiones futuras, slippage y gaps. El volumen se reduce al paso/capacidad disponible y nunca se sube al mínimo.
- Cargos de cuenta, comisiones diarias o ajustes sin asociación a deals de la posición no pueden imputarse fielmente: comparar neto agregado con el reporte del broker y documentar diferencias. Correcciones de historial posteriores a exportar una posición completa no reescriben filas ya emitidas.
- Las colas de transacciones tienen límites y el orden de llegada no es garantizado. Se reconstruye el historial en vez de acumular callbacks, conforme a [OnTradeTransaction](https://www.mql5.com/en/docs/event_handlers/ontradetransaction) y [HistorySelectByPosition](https://www.mql5.com/en/docs/trading/historyselectbyposition). Una transacción irrecuperable debe investigarse con ExecutionEvents y el historial del tester.
- Si el EA se retira con posiciones abiertas, no las cierra: sus SL/TP permanecen en el servidor. Registra UNFINISHED_AT_END; no inventa un trade completo. Reiniciar con posiciones/órdenes propias existentes falla porque no puede recuperar MFE/MAE completos. Usar runs limpios; no iniciar dos instancias con el mismo Magic/símbolo.
- Telemetría desactivada conserva las decisiones y el seguimiento, pero no exporta ni acumula medianas. Un error de apertura CSV con telemetría activa aborta la inicialización. Un fallo de escritura posterior se registra en Journal y IOFailure; no se fuerza el cierre de posiciones. Un cierre abrupto puede perder buffers y metadatos finales. La ausencia de metadatos completos invalida el análisis automático.
- Las medianas se ordenan al finalizar, no en cada tick. El costo por tick del motor virtual es proporcional al número de observaciones activas; las consultas de edad de barra solo se hacen al cambiar de barra.
- Exportaciones de agentes remotos/cloud no se recuperan automáticamente. Usar agentes locales para esta versión. RunID reduce colisiones y se verifica existencia antes de abrir los archivos; no es un coordinador distribuido entre instancias concurrentes mal configuradas.
- Diferencias frente a la estrategia original: controles de contrato/margen, rechazo de stops, reducción de volumen al límite, ausencia de reintentos, omisión de barra inicial y redondeo de TP a tick. No existe una comparación directa con su fuente o entradas/salidas; la reproducción ofrecida es conceptual.

Referencias adicionales: [OrderCalcProfit](https://www.mql5.com/en/docs/trading/ordercalcprofit), [CopyTicksRange](https://www.mql5.com/en/docs/series/copyticksrange), [FileOpen y sandbox](https://www.mql5.com/en/docs/files/fileopen).
