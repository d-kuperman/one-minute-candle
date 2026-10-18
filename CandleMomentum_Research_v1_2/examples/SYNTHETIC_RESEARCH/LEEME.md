# Ejemplo sintético, no es un backtest

Dos trayectorias BUY construidas a mano para verificar los archivos. No contienen precios descargados ni operaciones de una cuenta.

- a: riesgo 2 pips. Primero alcanza 1.5R; luego un gap llega a −1.5R. MFE=3 pips y MAE=3 pips. Los niveles hasta 1.5R tienen TARGET_BEFORE_SL; 2R a 5R tienen SL_BEFORE_TARGET.
- b: no resuelve objetivos ni stop; vence el horizonte. MAE inicial=0.2 pips por spread. El gran tick del instante de vencimiento no se incluye.

En ALL, para 1R: Hits=1, Stops=0, CensoredForTarget=1. HitPctResolved=100%, HitPctAllValid=50%. Esto NO demuestra una estrategia rentable: la muestra es inventada y mínima.

Analysis.json y TickReplayAudit.csv muestran los resultados de verificar estos datos. Los metadatos son mínimos para probar el analizador; una corrida real exporta todas las claves documentadas.
