# One Minute Candle EA (MetaTrader 5)

Asesor Experto (EA) en MQL5 diseñado para investigar y optimizar estrategias de continuación en velas de intención (cuerpo amplio y poca mecha) combinadas con filtros de retorno a la media o tendencia mediante 1 o 2 EMAs multi-temporalidad.

## Características Principales

- **Filtro de Dirección Multi-Temporalidad (1 o 2 EMAs):**
  - **Reversión a la EMA:** Busca compras cuando toda la vela gatillo cierra por debajo de la(s) EMA(s) y ventas cuando cierra por encima.
  - **A favor de la EMA (Tendencial):** Busca compras por encima de la(s) EMA(s) y ventas por debajo.
  - **Ignorar EMA:** Opera ambas direcciones basándose únicamente en la formación de la vela gatillo.
  - **Distancia Mínima a la EMA:** Permite exigir una separación mínima en pips respecto a la EMA más cercana antes de habilitar entradas.
- **Vela Gatillo Parametrizable:**
  - Selección de temporalidad (`M1`, `M3`, `M5`, `M15`, `M30`, `H1`, `H4`).
  - Porcentaje mínimo del cuerpo respecto al rango total (`High - Low`).
  - Rango mínimo y máximo en pips (`High - Low`).
- **Gestión Dinámica de Riesgo, Break Even y Trailing Stop:**
  - Tamaño de posición calculado automáticamente en base al `% del Balance actual` para cualquier instrumento (Forex, Metales, Índices, Futuros, Cripto).
  - **Stop Loss inicial ($1R$):** En el `Low` de la vela gatillo para compras y en el `High` para ventas.
  - **Break Even (BE) y Trailing Stop (TS) Tick a Tick:** Ajustables mediante desplazamientos positivos o negativos sobre el ratio `1:1` (`1.0R`).
- **Filtros Operativos:**
  - Control de operaciones simultáneas (solo permite agregar posiciones en la misma dirección de la orden activa).
  - Filtro de horario de operación y filtro de spread máximo.

## Instalación en MetaTrader 5

1. Copia el archivo `OneMinuteCandle_EA.mq5` (o el compilado `OneMinuteCandle_EA.ex5`) dentro de la carpeta de datos de tu MetaTrader 5:
   `Archivo -> Abrir carpeta de datos -> MQL5 -> Experts`
2. En el panel **Navegador** de MT5, haz clic derecho sobre **Asesores Expertos** y selecciona **Actualizar** (o compílalo desde MetaEditor con `F7`).
3. Abre el **Probador de Estrategias** (`Ctrl + R`) para realizar backtesting u optimización de parámetros.
