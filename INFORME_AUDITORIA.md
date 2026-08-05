# 🔍 Informe de Auditoría — FENLORA CLOUD POS

**Fecha:** 5 de agosto de 2026
**Alcance:** dinero (precios, adiciones, impuestos, propinas), caja, reportes, perfiles/roles de empleados y el ciclo completo del pedido con dos dispositivos.
**Método:** simulaciones internas automatizadas (127 verificaciones) que reproducen casos reales de clientes y cruzan la matemática esperada contra lo que hace el sistema.

---

## ✅ Resultado general

**127 verificaciones, todas correctas** tras aplicar 2 correcciones. Se encontró **1 error de contabilidad** y **1 riesgo** (doble cobro), ambos corregidos. El resto del sistema quedó verificado y cuadrando.

---

## 🛠️ Lo que se corrigió

### 1. "Ventas" incluía las propinas (error de contabilidad)
Antes, el total de **Ventas** —tanto en Caja como en Reportes— sumaba la propina. La propina no es venta del negocio (es del mesero), así que las ventas salían infladas.

**Corregido:**
- **Ventas (sin propina):** ahora es solo lo que vendió el negocio (productos), sin propina.
- **Propinas:** siguen mostrándose aparte.
- **Total recibido:** tarjeta nueva = ventas + propinas (lo que realmente entró).
- **Efectivo esperado en caja:** SIGUE incluyendo la propina pagada en efectivo, porque ese dinero físicamente está en la caja (así el arqueo cuadra con lo que cuentas).
- En Reportes, "Medios de pago" se renombró a **"Recibido por medio (incluye propina)"** para que quede claro.

### 2. Riesgo de doble cobro (doble toque en "Cobrar")
Si se tocaba "Cobrar" dos veces rápido, se podían generar dos facturas de la misma mesa.

**Corregido:** ahora si una cuenta ya fue facturada, un segundo cobro se ignora con el aviso "⚠️ Esta cuenta ya fue facturada". Aplica al cobro normal y al cobro dividido.

---

## 🔎 Lo que se revisó y quedó CORRECTO (sin cambios)

**Precios y adiciones**
- Suma base + variantes + adiciones, por cantidad (ej: base 5.000 + 2 adiciones de 1.000 = 7.000 c/u × 2 = 14.000). ✔
- Variante y adiciones al mismo tiempo suman bien (ej: tamaño grande +3.000 y 2 extras = 7.500). ✔
- Cortesías: no se cobran (valor 0) pero sí quedan en el pedido. ✔
- Descuentos por plato y descuento al cobrar: se restan bien, sin doble descuento, y nunca dan total negativo. ✔

**Caja**
- Efectivo esperado = base + ventas en efectivo + ingresos − egresos. ✔ (ej: 100.000 + 25.500 + 50.000 − 20.000 = 155.500)
- Solo cuenta las facturas del turno abierto (no mezcla turnos anteriores). ✔
- Pagos con tarjeta no suman al efectivo esperado. ✔
- Arqueo/cierre: diferencia = contado − esperado, y guarda el desglose por medio. ✔

**Reportes**
- Total de ventas, propinas, ticket promedio, nº de facturas, productos más vendidos, por medio, por hora, por día y por mesero: cuadran. ✔
- Anulaciones: cuenta, valor, por motivo, por producto y por mesero. ✔

**Perfiles y roles**
- PIN de empleados: se guarda cifrado (SHA-256), verifica el correcto y rechaza el incorrecto. ✔
- Mesero ve Mesas y Cocina; NO ve Caja, Reportes ni Productos. ✔
- Cajero ve Caja; NO ve Reportes. ✔
- Cocina solo ve Cocina. ✔
- Admin ve todo. ✔
- Cobrar: solo admin y cajero. Marcar en cocina (listo/entregado): solo cocina y admin. ✔

**Ciclo completo con 2 dispositivos (mesero + admin)**
- Pedido → cocina → listo (aviso al mesero con botón y al admin solo con X) → precuenta (mesa "por cobrar" + aviso al admin) → facturar (mesa "facturada, falta pago") → confirmar pago (mesa liberada en ambos). ✔
- Cobro dividido: genera una factura por persona, la suma cuadra con el total y solo la primera lleva los productos (no duplica). ✔
- Anulación de un producto ya enviado: pide motivo, lo registra para reportes y lo saca del pedido. ✔
- Mesas unidas (incluidas no contiguas, ej: 3+5): se ven completas en todos los dispositivos. ✔

---

## 📌 Notas / recomendaciones a futuro (no urgente)

- **Impuestos (IVA/INC):** hoy el sistema trabaja con precios finales (lo que ve el cliente). Cuando actives facturación DIAN real habrá que definir si el precio incluye o excluye impuesto y desglosarlo. Queda pendiente para la fase fiscal.
- **Stock/Kardex:** no entró en esta auditoría (es de otra fase). Cuando lo activemos, se audita el descuento de inventario por venta.
- **Pasarela de pagos:** el "Confirmar pago" manual queda listo para reemplazarse por el aviso automático de la pasarela cuando la conectemos.

---
*Auditoría realizada con 127 pruebas automáticas internas. Todo en verde.*
