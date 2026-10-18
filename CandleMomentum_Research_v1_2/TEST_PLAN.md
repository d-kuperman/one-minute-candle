# Plan de integridad V1.2

No optimizar ni seleccionar parámetros por rentabilidad en estas pruebas. Usar un período corto con ticks reales para integración, después ampliar a distintos regímenes y temporalidades. Guardar servidor, build de MT5, modelo de ticks, fechas, parámetros, reporte HTML del tester y carpeta RunID.

## Evidencia disponible y pendiente

El compilador real de MetaEditor verificó EA y scripts; `validation/` conserva logs. Los tests Python ejercitan CSV sintéticos con resultados conocidos, corrupción deliberada y replay. **No equivalen a ejecutar el EA ni a conciliar operaciones con MT5.** El script MQL de pruebas se compila, pero su ejecución requiere un terminal con contexto de símbolo disponible. El tester aislado no arrancó sin cuenta configurada. Estado detallado en `validation/ESTADO.md`.

Para ejecutar pruebas MQL: copiar esta carpeta completa a `MQL5/Scripts/CMR_Tests/` (incluyendo el EA un nivel por encima de `tests/CMR_UnitTests.mq5`), compilar el script y ejecutarlo desde el Navegador sobre un gráfico EURUSD de un terminal configurado. No activar la producción del EA para esta prueba: los handlers incluidos tienen otros nombres, y OnStart solo llama a funciones matemáticas/virtuales. Mantener inputs por defecto. Exigir `CMR_UNIT_RESULT ... failures=0` y guardar `MQL5/Files/CMR_UnitTests.txt` más Journal. No hay llamadas a SendSignal desde OnStart.

Pruebas Python:

```powershell
python -m unittest discover -s tests -v
```

## Matriz de aceptación

| N.º | Caso | Procedimiento y resultado exigido |
|---|---|---|
| 1 | Alcista 80% | OHLC 1.10002/1.10020/1.10000/1.10018. MakeSignal da BUY, BodyPercent≈80 y BodyPass=1. Caso incluido en script MQL. |
| 2 | Bajista 80% | Invertir apertura/cierre anteriores. SELL, mismo filtro inclusivo. Script MQL. |
| 3 | Cuerpo inferior | Reducir cuerpo a 70%, BodyPass=0. En Trading no entra; en Research universo libre se conserva. |
| 4 | Rango en umbral | High−Low=0.0002; con mínimo 2 pips debe pasar, tolerancia numérica 1e−8 en variables de filtro. |
| 5 | Rango inferior | High−Low=0.000199; no debe pasar 2 pips. Script MQL. |
| 6 | ATR faltante | CopyBuffer no disponible o referencia inválida: campos ATR vacíos y ATRPass=0. ATR/combinado rechazan; PIPS no depende de ATR. Python prueba vacíos frente a cero. |
| 7 | RangeATR=1 | Rango=0.0002, ATR anterior=0.0002. Ratio=1, sin confundir con 2 pips. |
| 8 | Vela grande | Con máximo 0 no recorta; máximo positivo en modo correspondiente sí. Máximos inactivos no afectan selección. Verificar con ticks/histórico controlado. |
| 9 | Combinado | Construir dos velas: una pasa pips pero no ATR y otra al revés. Ninguna pasa combinado. Solo la que pasa ambos+cuerpo genera señal comercial. |
| 10 | SL | BUY usa exactamente Low y SELL exactamente High. Nivel fuera de rejilla o lado ejecutable inválido rechaza sin desplazarlo. |
| 11 | TP | Revisar RR=0.5, 1, 2 y 3. Precio previsto±R*RR redondeado al tick. Validar cuatro y cinco dígitos; RR efectivo refleja fill. |
| 12 | Riesgo monetario | Balance conocido, riesgo 1%; comparar lote con OrderCalcProfit a SL y paso. Pérdida de precio prevista ≤presupuesto. Repetir moneda USD y otra moneda disponible. |
| 13 | Volumen mínimo | Configurar presupuesto que produzca lote menor al mínimo. VOLUME_BELOW_MINIMUM; no subir lote. Script MQL prueba floor; integración debe confirmar rechazo comercial. |
| 14 | Spread | Cotización de spread >límite rechaza solo comercialmente. Igualdad pasa. Límite cero con filtro activo rechaza spread positivo. |
| 15 | Margen | Depósito/apalancamiento controlados, riesgo grande sin volumen mínimo impeditivo; OrderCalcMargin/OrderCheck rechaza. No enviar una operación descubierta. |
| 16 | Opuestas | Abrir BUY propia y presentar señal SELL; OPPOSITE_POSITION, aunque hedging lo permita contractualmente. |
| 17 | Simultáneas | Hedging acepta BUY adicionales con bandera activa y capacidad suficiente. Probar máximo 1/2/0, bandera false y límite agregado activo/inactivo. |
| 18 | Deals/posición | Forzar o seleccionar fills parciales si el entorno los permite. Una sola fila final por POSITION_IDENTIFIER, todos los order/deal IDs, sumas sin duplicar callbacks. Python valida exportación sintética con varios deals; prueba de broker pendiente. |
| 19 | No duplicados | Varias cotizaciones por barra: una evaluación. Rechazo no reintentado. Pérdida de datos seguida de recuperación no dispara vela vieja. Cruzar IDs únicos con analyzer. |
| 20 | Sin lookahead | Verificar en fuente CopyRates(shift 1), CopyBuffer(shift 2); comparar ATRReference con indicador de barra anterior a gatillo. Primera barra tras adjuntar no opera. |
| 21 | MFE/MAE | Trayectoria BUY/SELL con extremos conocidos y spread inicial. No negativos; timestamps del primer extremo. Trading solo mientras abierto, incluye ejecución de salida. Research no termina en TP. |
| 22 | Primera llegada | Trayectoria primero 1.5R y luego stop. Objetivos ≤1.5R ganan llegada, superiores pierden. Invertir orden: ninguno gana. Script MQL y replay sintético. |
| 23 | Censura | Horizonte y fin de histórico con niveles pendientes: censurar esos niveles. Los ya alcanzados permanecen resueltos. No sumar censurados a Stops. Python comprueba contadores. |
| 24 | Modos separados | Research no debe generar ningún deal ni Trades.csv; Trading no debe producir retorno de cartera virtual. Revisar historial y tipos de archivo. |
| 25 | CSV | Ejecutar analyze.py sobre exports reales; exigir PASS, filas consistentes, IDs únicos, siete niveles por observación, medias/medianas ALL recalculadas y netos coherentes. Python prueba corrupción y duplicados. |
| 26 | Coincidencia MT5 | Conciliar cada POSITION_IDENTIFIER contra HistorySelectByPosition/reporte: volúmenes, fills, bruto, comisiones, swap, fees y neto. Identificar cargos no asignables y abiertas al final. Exigir diferencia explicada, no ocultarla. Pendiente de integración. |
| 27 | Telemetría on/off | Mismo período, datos e inputs salvo telemetría/Magic independiente. Comparar secuencia de deals en reportes MT5. No basarse solo en beneficio final. En vivo la carga temporal puede modificar eventos recibidos. |
| 28 | Hedging/netting | Preset original debe iniciar en hedging y rechazar netting incompatible. Netting máximo 1 debe evitar suma de posiciones y bloquear posiciones ajenas del símbolo. |
| 29 | Cero/pocos trades | OnTester debe penalizar n<N, incluido n=0. Research siempre score negativo reservado. No usar PF infinito para premiar una sola ganancia. |
| 30 | Gaps/saltos | Un tick salta varios objetivos: todos alcanzados con igual timestamp. Gap de stop produce MAE>1R cuando corresponda. El tick de inicio de barra N no entra en extremos anteriores. Python replay cubre estos casos. |

## Pruebas adicionales de datos y ejecución

- Repetir modo PIPS, ATR, combinado y desactivado con todos los TF admitidos. Revisar ATR de shift 2 manualmente en al menos cinco señales por ejecución.
- Comparar períodos cortos y largos con los mismos extremos temporales observados al agrupar firmas. Un mismo conteo o beneficio no es prueba de selección equivalente.
- Crear dos runs repetidos con inputs idénticos: mismos IDs/firmas y resultados con el mismo histórico determinista. RunID y archivos deben ser distintos.
- Probar período con mercado cerrado, ticks inválidos, rango cero, doji, SL no representable, stop level elevado, volumen máximo y SYMBOL_VOLUME_LIMIT. Ningún caso debe crear NaN/infinito en CSV.
- Cerrar externamente una posición de prueba o dejar cierre de fin del tester: ExitReason debe identificar el evento real y no inventar SL/TP. Las salidas extraordinarias se conservan.
- Las observaciones superpuestas no consumen posiciones ni riesgo agregado virtual. Comparar número de observaciones con velas direccionales elegibles independientemente del estado de las anteriores.
- No imputar una llegada intravela desde High/Low. Si faltan ticks o el replay difiere, conservar la diferencia como problema de cobertura hasta resolverla.

## Criterio de liberación para investigación

Compilación sin errores/advertencias, script MQL sin fallos, integridad CSV de corridas reales y conciliación comercial documentada. Al menos una prueba de paridad on/off y una prueba por modo de cuenta aplicable. Auditar extremos/primeras llegadas contra ticks en una muestra que incluya gaps y censura. Hasta completar esos pasos, el sistema está implementado y compilado, pero **no certificado por integración estadística/comercial**.
