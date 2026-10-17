# Datos faltantes para una próxima auditoría

Este documento propone registros para una etapa posterior. No se ha modificado el EA ni incorporado filtros, reglas o parámetros nuevos.

## Prioridad 1: cobertura e identidad

- Inicio/fin efectivos con fecha y hora del primer/último tick y barras por día; evidencia explícita de inclusión del viernes 16/10/2026.
- Zona horaria y offset UTC del servidor en cada fecha, con cambios estacionales si corresponden.
- Hash y versión del EA ejecutado, parámetros completos, build de MT5, journal y configuración del probador.
- Identificador nativo de posición, tickets de orden/deal y relación de cada ejecución parcial con su posición.
- Especificación del símbolo: contract size, tick size/value profit/loss, divisa de cálculo, lotes mínimos/máximos/paso, comisión, swap, margen, stops level y freeze level.

## Prioridad 2: señal, riesgo y entrada

- Timestamp de vela gatillo, OHLC M1, rango en pips y porcentaje del cuerpo.
- Valor EMA200 M15, timestamp/índice de la barra M15 empleada y cierre gatillo. No sustituir por precio ejecutado.
- Bid/Ask y spread al detectar señal, enviar orden y ejecutarla.
- Precio de referencia solicitado, precio ejecutado y timestamps con milisegundos cuando existan.
- Balance base, riesgo nominal, riesgo monetario calculado, volumen antes/después de redondeo y factores monetarios utilizados.
- SL solicitado y SL efectivamente aceptado al abrir; posibles rechazos y retcodes.

## Prioridad 3: trayectoria y salida

- Cotización Bid/Ask intratrade o extremos MFE/MAE por posición con timestamp y convención explícita. Para BUY, considerar cotización de liquidación Bid; para SELL, Ask.
- Primer instante en que se alcanza +1R; primer intento y primera aceptación de trailing.
- Cada SL anterior, nuevo SL solicitado, SL aceptado, timestamp, retcode, stops/freeze levels y motivo de rechazo.
- Motivo técnico de cierre, SL vigente, cotización de activación, precio ejecutado y costes efectivos.
- Series de balance, equity, margen y exposición en cada evento relevante/tick para drawdown y riesgo flotante.

## Qué permitirán comprobar

1. Reglas de señal: EMA, color, cuerpo y rango; sin inferencias a partir de los fills.
2. Activación exacta en +1R, distancia de trailing y ausencia de retrocesos del stop.
3. Captura = resultado de precio/MFE de precio y devolución = MFE de precio−resultado de precio, con una versión neta separada si se desea. Definir tratamiento de MFE cero y costes antes de calcular porcentajes.
4. Costes/R, desviaciones de entrada y salida y pérdidas al stop frente al riesgo proyectado.
5. Distancia a EMA y tamaño de vela frente a resultados, sin confundir correlación con capacidad de selección fuera de muestra.

El XLSX actual solo contiene correlaciones agregadas MFE/MAE: no alcanza para estos cálculos. Los parámetros EnableDebugLogs y ExportTradesCSV están en false. No se presume qué columnas producirían al activarse; primero se debe verificar su esquema y suficiencia.
