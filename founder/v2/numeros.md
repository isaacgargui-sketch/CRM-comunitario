# Movilapp v2: números del alcance acotado

Cálculo reproducible: `python3 founder/v2/calculo.py`. Todo en USD a $1.510. Costos tomados del modelo vivo v4 de Movilapp salvo donde dice *estimación*.

## Por qué cambió el auto (el hallazgo que ordena todo)

Con los costos del propio modelo, un Versa 0 km a $50.000 por turno con 40 autos y una estructura chica (USD 10.760/mes) **no alcanza el punto de equilibrio contable ni con 85 % de ocupación**: lo necesitaría en 91 %. El EBITDA recién es positivo arriba de 69 %.

| Escenario: 40 Versa 0 km, $50.000 | 66 % | 75 % | 80 % | 85 % |
|---|---|---|---|---|
| EBITDA / mes | −766 | 1.938 | 3.440 | 4.942 |
| Resultado / mes (con amortización e intereses) | −7.651 | −4.947 | −3.444 | −1.942 |

Con un **Versa usado de 24 meses** al valor que el propio modelo usa como reventa (ARS 10,4 M = USD 6.887), el mismo crédito compra un 50 % más de autos y la relación facturación/valor del auto entra en la banda de deRentas (88–133 %).

## Supuestos

| Supuesto | Valor | Fuente |
|---|---|---|
| Tarifa por turno (con IVA) | $50.000 piso, **$55.000 objetivo** | Modelo v4 / objetivo a validar en Etapa 0 |
| Contribución por día alquilado | USD 24,1 (a $50k) · 26,6 (a $55k) | Neto de IVA, IIBB 4,5 %, mora 5 %, cobranza 1,2 %, débitos y créditos |
| Costo del auto | USD 6.887, sin crédito fiscal de IVA | Reventa a 24 m del modelo v4 (conservador: sin crédito de IVA) |
| Valor a los 48 meses | 75 % del costo | *Estimación*, a confirmar con tabla de usados de AGN |
| Mantenimiento | $2,9 M/año × 1,25 | Modelo v4 + 25 % por auto usado (*estimación*) |
| Seguro, siniestros, patente, GPS | según modelo v4 | Modelo v4 |
| Prendario | 70 %, 36 meses, 14 % real | Modelo v4 (**confirmar que el banco preste sobre usados**) |
| Estructura en régimen | USD 10.760/mes | 3 personas (USD 6.360, costo cargado del modelo) + servicios AGN a precio de mercado USD 2.500 + sistemas 600 + referidos 800 + playa 500 (*estimación*) |
| Estructura en piloto | USD 6.000/mes | *Estimación* |
| Costo de arranque | USD 60.000 | Validación 15k + legal/fiscal 20k + plataforma mínima 25k (*estimación*) |
| Rampa | 10 autos m1–4 (capital propio) → 20/30/40/50 en m5–8 | Plan v2 |

## Resultados: 50 autos usados

| Tarifa | Ocupación | Crédito usado | EBITDA año 1 | Resultado año 1 | Capital propio máximo | EBITDA/mes en régimen | Resultado/mes en régimen | Ocupación de equilibrio |
|---|---|---|---|---|---|---|---|---|
| $50.000 | 70 % | 241.056 | −20.350 | −65.216 | 243.180 | 1.239 | −4.035 | 81 % |
| $50.000 | 80 % | 241.056 | 5.299 | −39.568 | 217.531 | 4.904 | −371 | 81 % |
| $50.000 | 85 % | 241.056 | 18.123 | −26.744 | 204.707 | 6.736 | 1.461 | 81 % |
| **$55.000** | **80 %** | **241.056** | **27.210** | **−17.657** | **195.620** | **7.835** | **2.560** | **74 %** |
| $55.000 | 70 % | 241.056 | −1.003 | −45.870 | 223.833 | 3.804 | −1.470 | 74 % |
| $55.000 | 85 % | 241.056 | 41.317 | −3.550 | 187.184 | 9.850 | 4.576 | 74 % |

**Lectura honesta:**
- El caso base ($55.000, 80 %) entra en los USD 200.000 propios **sin colchón**. A $50.000 hacen falta USD 205–245 mil: en ese caso se frena en 40 autos.
- El año 1 da pérdida contable en todos los escenarios (rampa + piloto). En régimen, el negocio de 50 autos es **chico**: entre USD 2.500 y 4.600 de resultado por mes en los buenos escenarios. La fase 1 compra una prueba, no una renta.
- Lo que mueve la aguja, en orden: **ocupación** (contratos semanales con lista de espera), **tarifa** ($55.000 con todo incluido) y **turno compartido** (dos choferes por auto a 1,5×: con 62 autos a 66 % da EBITDA ≈ USD 12.100/mes; es *estimación* con +40 % de desgaste).
- Del crédito de USD 300.000 se usan ~241.000; quedan ~59.000 de margen para autos de reemplazo o turno compartido.
