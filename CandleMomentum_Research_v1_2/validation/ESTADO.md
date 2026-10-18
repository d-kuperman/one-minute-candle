# Estado de validación — 17 de octubre de 2026

## Completado

- Desarrollo nuevo, autocontenido, sin dependencias del código previo de la carpeta.
- Compilación con MetaEditor64 instalado: fuente principal, script MQL de pruebas y exportador histórico. Logs conservados; exigir la última línea `0 errors, 0 warnings`.
- 20 tests Python ejecutados y aprobados: CSV válidos/corruptos, duplicados, censura, niveles, medias/medianas, costes netos, múltiples deals sintéticos por posición y replay de ticks con gap y límite de horizonte.
- Presets completos y documentación de inputs, columnas, arquitectura, instalación, análisis y limitaciones.

## Pendiente de ejecución en MT5 configurado

- Ejecutar `CMR_UnitTests` y confirmar failures=0. Se compiló y cargó en el terminal aislado, pero no se obtuvo salida de ejecución con el contexto de símbolo/cuenta disponible; no se cuenta como prueba aprobada.
- Ejecutar el EA en Strategy Tester con ticks reales y auditar sus CSV. Se intentó con un terminal temporal aislado, sin credenciales ni negociación habilitada. MT5 informó: **tester not started because the account is not specified**. No se produjo un backtest válido.
- Conciliar Trades.csv con el reporte de MT5; probar fills parciales, cuentas hedging/netting, restricciones del broker y paridad con telemetría apagada.
- Contrastar excursiones reales del EA con el exportador/replayer de ticks históricos.

La compilación y los tests auxiliares no sustituyen estas pruebas. No se ejecutaron optimizaciones, no se buscaron parámetros rentables y no se afirma identidad de operaciones con una versión anterior.

El terminal temporal se creó solo para validación y se cerró. No se copiaron credenciales ni se enviaron órdenes a una cuenta real.
