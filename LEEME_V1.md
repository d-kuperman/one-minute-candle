# EMA200 Mean Reversion M1 — V1.0

## Entrega y verificación ejecutada

- `EMA200_MeanReversion_M1_V1.mq5`: fuente completo, sin dependencias externas.
- `EMA200_MeanReversion_M1_V1.ex5`: binario generado con MetaEditor instalado en `E:\metatrader 20k\metaeditor64.exe`.
- `compile.log`: compilación final con **0 errores, 0 advertencias**.
- `verificar_fuente.py` / `validacion_estatica.json`: 18 comprobaciones estructurales aprobadas.
- `verificar_formulas.py` / `validacion_formulas.json`: 16 comprobaciones aprobadas, evaluando en Python expresiones extraídas del fuente (umbrales y dirección de señales en cuatro/cinco decimales, ejemplos de distancia BUY/SELL). No ejecutan el runtime MQL5.

**No se ejecutó Strategy Tester, backtest con ticks reales, ensayo de reinicio en MT5 ni prueba de órdenes contra un servidor.** La compilación, revisión del código y comprobaciones de fórmulas no demuestran rentabilidad ni sustituyen esas pruebas de integración.

## Arquitectura

`OnTick` gestiona primero el trailing. A continuación consume una nueva vela M1 una sola vez y llama a `Signal` y `Enter`. La temporalidad del gráfico no participa en los cálculos. Al adjuntar/reiniciar se espera la siguiente M1: no se recuperan señales atrasadas.

`Signal` lee exclusivamente OHLC M1 shift 1. Localiza la M15 correspondiente al instante de apertura M1 y selecciona una M15 cuyo cierre sea anterior o igual a ese instante. `CopyBuffer` lee la EMA confirmada. Si falta historia o falla la lectura, esa oportunidad se descarta. La M1 debe ser contigua a la nueva vela; no se usa una vela anterior a un hueco de mercado como señal tardía.

`Enter` conserva exactamente Low/High como SL, comprueba su incremento permitido y restricciones de stops, spread, posiciones, lotaje, margen y `OrderCheck`. Calcula el volumen hacia abajo usando `OrderCalcProfit` y un capital base constante. Envía una sola orden de mercado con SL y TP=0; no amplía el stop ni reintenta entradas. Prioriza FOK y admite IOC; rechaza símbolos sin esos modos para evitar remanentes pendientes. Comprueba los retcodes, incluidos parciales y solicitudes todavía en proceso.

`Recover` conserva el precio real y el SL original para obtener R. Si es necesario recurre a `DEAL_SL` de las entradas, nunca al SL actual. Reconcilia cambios del precio medio/volumen debidos a fills de la misma apertura. El presupuesto no incluye comisiones futuras desconocidas; el riesgo efectivo estimado de precio se registra después del fill.

`Manage` usa Bid en BUY y Ask en SELL, guarda los extremos favorables/adversos y mantiene una distancia fija por operación. El SL candidato deriva del mejor precio observado y se redondea al tick más cercano. Solo se envía si mejora al menos un tick y cumple stops/freeze. Una restricción conserva el SL; se vuelve a evaluar en ticks posteriores. No hay llamadas a cierre manual, TP, break-even independiente ni salidas por EMA/horario/señales.

`OnTradeTransaction` reconcilia ejecuciones e historial, incluso aperturas/cierres muy rápidos. `ReportClosed` suma beneficios, comisiones, swap y fees del historial de la posición y clasifica el motivo real. El CSV contiene eventos OPEN, CLOSE, REJECT, TRAIL_ACTIVATE y TRAIL_MOVE; para una fila por operación cerrada, seleccionar `event=CLOSE`. Los eventos intermedios tienen resultados monetarios todavía no finales.

## Instalación y compilación

1. En MT5: Archivo → Abrir carpeta de datos.
2. Copiar el `.mq5` a `MQL5\Experts\EMA200_MeanReversion_M1_V1.mq5`.
3. Abrirlo con MetaEditor y pulsar F7. También se entrega el `.ex5` compilado; puede copiarse a la misma carpeta.
4. Actualizar Asesores Expertos en el Navegador de MT5.
5. Usar Strategy Tester antes de habilitar operaciones en una cuenta. No se modificó ninguna instalación ni se adjuntó el EA a un gráfico durante esta entrega.

## Primer backtest reproducible

- EA: EMA200_MeanReversion_M1_V1.
- Símbolo: EURUSD del bróker, con sus propiedades y costes históricos. Se admiten sufijos/prefijos verificando divisa base EUR y de beneficio USD, y cotización de 4/5 decimales.
- Modelo: **Cada tick basado en ticks reales**. M1 como período del probador por comodidad; el código fuerza M1 y M15 internamente.
- Depósito inicial: por ejemplo USD 5.000. `FixedInitialBalance=0` y `RiskPercent=1.0` dan un presupuesto constante de USD 50. Si se elige otra divisa de cuenta, el cálculo monetario usa esa divisa.
- Mantener todos los parámetros predeterminados. `MaxSlippagePoints=10`: equivale a 1 pip en cinco decimales y 10 pips en cuatro, porque su unidad es points. No cambiar esa unidad al comparar resultados.
- Para la primera auditoría, activar `ExportTradesCSV=true`; dejarlo desactivado en optimizaciones. `EnableDebugLogs=false` conserva los registros esenciales de rechazos/ejecuciones/errores.
- Sin optimización. Elegir y guardar fechas, servidor, versión de terminal, depósito/divisa, apalancamiento, modo y retraso de ejecución, especificaciones del símbolo, comisiones y parámetros. No se seleccionó un período de investigación en esta entrega.
- Asegurar suficiente historia previa M15 para la EMA (al menos 200 velas disponibles); el EA omite evaluaciones si el indicador no está listo. Para comparar resultados, mantener también igual la historia previa disponible y el modelo de ticks.
- Revisar Diario, calidad/disponibilidad de ticks y reporte final. El probador puede liquidar posiciones al final de la prueba: eso no es una salida voluntaria del EA y debe analizarse separadamente según el motivo real registrado.

Inputs predeterminados: EMA_Period=200, MinBodyPercent=80, MinCandleRangePips=2, MaxCandleRangePips=0, RiskPercent=1, FixedInitialBalance=0, UseSpreadFilter=true, MaxSpreadPips=1, TrailingActivationRR=1, TrailingDistanceRR=1, MaxOpenPositions=1, MagicNumber=2001501001, MaxSlippagePoints=10, EnableDebugLogs=false, ExportTradesCSV=false.

`MaxOpenPositions` se expone pero no permite superar el límite absoluto V1 de una posición EURUSD aunque se configure mayor que uno; valores menores que uno se rechazan. No cambiar parámetros durante una operación si se desea un experimento homogéneo. La distancia y activación del trailing se guardan por operación.

## Persistencia, archivos y CSV

Fuera del tester, el capital se almacena en `MQL5\Files\EMR1_<identidad>_capital.bin`; identidad derivada de servidor, cuenta, símbolo y magic. No caduca por inactividad. Un capital manual positivo sustituye la base persistida. Mantener cuenta/símbolo/magic al reiniciar; si se quiere iniciar un experimento nuevo, establecer explícitamente el nuevo capital manual, sin posiciones abiertas. Un archivo de capital inválido bloquea el arranque en vez de recapturar silenciosamente el balance actual.

El estado se guarda en un archivo binario independiente: SL original, entrada, R, distancias, extremos, activación y metadatos. Cada extremo nuevo o cambio relevante se persiste. Si falta el archivo y existe una posición, se reconstruye R desde el historial y se marca `recovered_incomplete_metrics=1`; no se inventan OHLC/EMA/instante de activación ni extremos anteriores. Los ceros de esos campos en esa situación significan dato no recuperado. Sin historial suficiente para recuperar el SL original, se informa el error y no se modifica el stop a ciegas.

El tester no lee ni escribe los archivos de estado/capital del uso real: cada pasada captura su propio depósito o usa el capital manual. El CSV está en la carpeta `MQL5\Files` del terminal o agente de prueba correspondiente; su nombre se imprime en el Diario. Sus horas son del servidor/tester, no de la zona horaria de Windows.

`net_R` = beneficio neto monetario / riesgo monetario efectivo estimado al abrir. `gross_pips` usa la salida media ponderada y la entrada real. `slippage_pips` es positivo para ejecución adversa. MFE/MAE se miden con cotizaciones de cierre Bid/Ask observadas por el EA y se incorpora el precio de salida. Comisiones, swap y fees se suman cuando están ligados a los deals de esa posición; ajustes contables posteriores o cargos independientes pueden no ser atribuibles.

Solo se clasifica `TRAILING_BREAKEVEN_NET` cuando el neto es prácticamente cero (tolerancia numérica 1e-8). Una salida al precio de entrada con comisiones negativas se clasifica como pérdida neta por costes. SL inicial, trailing con pérdida por ejecución, trailing con pérdida por costes, trailing con beneficio y razones extraordinarias del servidor se distinguen.

## Revisión de las 20 condiciones obligatorias

Esta tabla documenta revisión del fuente; únicamente donde se indica «fórmulas» hubo ejecución adicional de expresiones en Python. Las comprobaciones de servidor siguen pendientes.

| # | Condición y resultado de revisión | Evidencia / prueba pendiente |
|---|---|---|
| 1 | BUY alcista debajo de EMA | Signal; fórmulas aprobadas |
| 2 | SELL bajista encima de EMA | Signal; fórmulas aprobadas |
| 3 | Cuerpo exactamente 80% aceptado | Fórmulas aprobadas, 4/5 decimales |
| 4 | Rango exactamente 2 pips rechazado | Fórmulas aprobadas, tolerancia solo de representación binaria |
| 5 | Rango >2 pips aceptado con demás condiciones | Fórmulas aprobadas |
| 6 | Mechas excesivas rechazadas | Fórmulas aprobadas |
| 7 | Spread superior al límite rechaza entrada | Enter; validar ticks en tester |
| 8 | Posición EURUSD propia/ajena bloquea otra | AnyPosition; validar netting y hedging |
| 9 | SL BUY Low / SELL High sin buffer | Signal/Enter; validar orden y fill |
| 10 | Riesgo sobre capital inicial, volumen hacia abajo | Enter; OrderCalcProfit/OrderCalcMargin; validar propiedades reales |
| 11 | Activación al alcanzar 1R | Manage; validar cotizaciones Bid/Ask en tester |
| 12 | SL no retrocede | Mejor extremo y mejora >=1 tick; ejemplos de distancia aprobados |
| 13 | BUY y SELL simétricos | Señales y ejemplos de distancia aprobados; falta ejecución integrada |
| 14 | Sin TP | Comprobación estructural aprobada |
| 15 | Sin cierres voluntarios | Comprobación estructural aprobada |
| 16 | Rechazo de modificación conserva SL | Retcodes y stops/freeze revisados; provocar rechazos en entorno de prueba |
| 17 | 4/5 decimales y tick size real | Fórmulas aprobadas; falta probar símbolos de ambas precisiones |
| 18 | EMA sin datos futuros | Guardia temporal de cierre y CopyBuffer revisados |
| 19 | R original tras reinicio | Persistencia + DEAL_SL revisados; falta ensayo real de reinicio |
| 20 | Retcodes reales | OrderSend y OrderCheck revisados; compilación sin advertencias |

Para completar la aceptación operativa: ejecutar modo visual con CSV; contrastar señal M1 y última M15 cerrada; verificar volumen y SL en historial; provocar spread alto/rechazo de stops/margen insuficiente; repetir en BUY y SELL; reiniciar el EA con trailing activo en una cuenta de prueba y comprobar que R y SL no retroceden. No confundir estas tareas pendientes con pruebas realizadas.

## Límites reales de ejecución

- Slippage, gaps y retraso pueden variar el fill, riesgo efectivo y salida; no es posible garantizar de antemano exactamente 1% con una orden de mercado. El EA no aumenta lotes ni fuerza cierres para corregir el fill.
- La desviación solicitada depende del modo de ejecución del bróker y puede no limitar el slippage en Market Execution. Las comisiones se agregan al coste real y no están presupuestadas como una estimación arbitraria.
- La distancia matemática R puede no coincidir con la rejilla de tick, especialmente con fills promediados. Se redondea al tick más cercano (error máximo medio tick); si no cumple stops/freeze, se conserva el último SL válido. El nivel inicial de la vela no se desplaza: si no pertenece a la rejilla permitida, se rechaza la entrada.
- El trailing requiere ticks y el terminal conectado. Con el terminal apagado permanece el último SL alojado en el servidor; no es posible reconstruir exactamente extremos ni modificaciones que nunca se observaron durante una desconexión.
- Un timeout/conexión perdida puede dejar resultado de apertura ambiguo. No se reenvía. La instancia queda bloqueada para nuevas entradas mientras no pueda reconciliar posición/orden; revisar historial y conexión antes de reiniciar. Esto evita duplicaciones, pero puede omitir oportunidades posteriores.
- Se bloquean instancias simultáneas de este EA para EURUSD dentro del mismo terminal/cuenta mediante archivo exclusivo. No existe atomicidad entre terminales distintos ni frente a operaciones manuales simultáneas. En netting no mezclar operaciones ajenas en la misma posición: cambia su composición e invalida las hipótesis del experimento.
- Si el servidor produce una anomalía (por ejemplo SL ausente tras un fill), se informa sin inventar una salida manual o ampliar el stop. La orden se envía siempre con el SL exacto.
- Stops del servidor, stop-out, operaciones externas y cierre final del tester se reportan según los deals disponibles. Un SL no garantiza el precio exacto de salida.

Referencias oficiales consultadas: https://www.mql5.com/en/docs/trading/ordersend y https://www.mql5.com/en/docs/constants/tradingconstants/dealproperties (semántica de retcodes y SL original del deal de entrada).
