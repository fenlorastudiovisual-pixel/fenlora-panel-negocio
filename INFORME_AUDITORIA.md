# 🔍 Informe de Auditoría COMPLETA — FENLORA CLOUD POS

**Fecha:** 5 de agosto de 2026
**Alcance:** TODO el proyecto — el recorrido del cliente de punta a punta (llega → se sienta → pide → cocina → sirve → cobra → se va) y **todas** las secciones/módulos: catálogo, categorías y áreas, importador Excel, menú QR, equipo/empleados, negocios (superadmin), login/multi-tenant, domicilios/llevar/online, mover comandas y platos, mesas unidas, dashboard, caja, reportes.
**Método:** 152 pruebas automáticas internas + 4 revisiones profundas del código en paralelo (una por grupo de módulos).

> Nota de honestidad: la **primera** auditoría cubrió el núcleo (dinero, caja, reportes, roles, ciclo del pedido). Esta **segunda** pasada cubrió el resto del proyecto y destapó varios bugs reales, ahora corregidos.

---

## ✅ Resultado

**152 verificaciones, todas en verde** tras aplicar las correcciones. Se encontraron **17 problemas** (2 en la 1ª pasada + 15 en la 2ª). Los de impacto ALTO y MEDIO quedaron corregidos; los menores quedan anotados abajo con transparencia.

---

## 🛠️ CORREGIDO en esta pasada completa

### 🔴 ALTA — Fuga de datos entre negocios (el más grave)
Como los negocios comparten el mismo navegador (multi-tenant por ruta), al cambiar de un negocio a otro se **arrastraban en memoria/caché los productos, facturas, caja y comandas del negocio anterior**, e incluso podía subirse el catálogo de un negocio a la base de datos de otro.
**Corregido:** al cambiar de negocio o cerrar sesión, ahora se **limpia todo lo del negocio anterior** (productos, facturas, anulaciones, cierres, caja, comandas, categorías, áreas, empleados, sesión). Además se agregó el filtro por negocio (`negocio_id`) a las consultas y borrados de productos como doble seguro.

### 🔴 ALTA — Eliminar una mesa ocupada dejaba el pedido "fantasma"
Borrar una mesa con consumo la quitaba del mapa pero **su pedido seguía vivo en cocina y en la nube**, sin poder cobrarlo ni cerrarlo.
**Corregido:** ahora al eliminar una mesa ocupada se **anula y libera su pedido** correctamente (avisando antes), y se sincroniza a los demás dispositivos. Igual para "eliminar todas las mesas" de un ambiente.

### 🔴 ALTA — Mover platos a una mesa unida los perdía
"Trasladar platos" a una mesa que estaba **unida** los mandaba a una comanda individual huérfana y **desaparecían** de la vista.
**Corregido:** ahora respeta la mesa unida (usa la comanda del grupo), no se pierde nada, y se sincroniza y guarda.

### 🟠 MEDIA — Mover una comanda dejaba el número de mesa viejo
Al mover la comanda de la Mesa 5 a la 8, el encabezado, la pestaña y el ticket seguían diciendo "Mesa 5".
**Corregido:** ahora el traslado actualiza el título a la mesa nueva, guarda y sincroniza (antes ni se guardaba ni se sincronizaba).

### 🟠 MEDIA — La config del menú QR no se guardaba
Los interruptores del QR (Pedir la cuenta, Llamar mesero, etc.) volvían a los valores por defecto al recargar.
**Corregido:** ahora se guardan y sobreviven al reinicio.

### 🟠 MEDIA — El importador de Excel pisaba ajustes del producto
Al re-importar una lista de precios (sin las columnas "Disponible"/"QR"/"Recomendado"), esos productos volvían a quedar disponibles/visibles aunque los hubieras ocultado.
**Corregido:** al **actualizar**, ahora solo se pisa lo que venga en el archivo; las columnas ausentes conservan el ajuste actual del producto.

### 🟠 MEDIA — La caja abierta sin internet se podía borrar al reconectar
Si abrías caja offline, al volver la señal un estado viejo de la nube podía **borrar la caja abierta y sus movimientos**.
**Corregido:** ahora un estado vacío o más viejo de la nube **no** pisa una caja abierta local; al reconectar se sube primero la caja local. (Marca de tiempo para no perder el más reciente.)

### 🟠 MEDIA — Domicilio sin dirección
Se podía crear un domicilio sin dirección de entrega.
**Corregido:** ahora exige la dirección antes de crear el pedido.

### 🟡 Otros arreglos
- **Doble cobro** (1ª pasada): un doble toque en "Cobrar" podía generar dos facturas. Corregido con bloqueo de idempotencia (normal y dividido).
- **"Ventas" incluía propinas** (1ª pasada): ahora Ventas es neto (sin propina), Propinas aparte, tarjeta "Total recibido", y el efectivo esperado sigue incluyendo la propina física en caja.
- **Nombres de categoría con comilla** (ej. `D'Café`) rompían los filtros: ahora se escapan.
- **CSV**: se neutraliza la inyección de fórmulas (celdas que empiezan por `= + - @`).
- **Configuración de mesas** (crear/generar/borrar) ahora se guarda de inmediato, no depende del autoguardado.

---

## 🔎 Verificado y CORRECTO (sin cambios)

- **Precios:** base + variantes + adiciones por cantidad; cortesías (no cobran); descuentos por plato y al cobrar (sin doble descuento ni negativos). ✔
- **Caja:** efectivo esperado, ingresos/egresos, tarjeta que no suma a efectivo, arqueo (contado vs esperado), historial y consolidado CSV (columnas alineadas, rango correcto). ✔
- **Reportes:** ventas netas, propinas, total recibido, ticket, top productos, por medio, hora, día, mesero, y anulados (cuenta/valor/motivo/producto/mesero). ✔
- **Empleados/roles:** PIN cifrado (SHA-256) que valida bien; permisos por rol correctos (mesero: mesas+cocina; cajero: +caja; cocina: solo cocina; admin: todo); cobrar solo admin/cajero; marcar en cocina solo cocina/admin. ✔
- **Catálogo/categorías:** guardar/editar/borrar producto, opciones/variantes, foto; borrar categoría reasigna a "Otros" (no deja huérfanos); borrar área reasigna; renombrar propaga; importador deduplica por nombre. ✔
- **Ciclo completo con 2 dispositivos:** pedido → cocina → listo (aviso a mesero con botón y a admin solo con X) → precuenta (por cobrar + aviso admin) → facturar (facturada, falta pago) → confirmar pago (liberada en ambos); mesas unidas no contiguas se ven completas en todos. ✔
- **Pedidos no-mesa:** llevar/domicilio/online se cobran y cierran bien (no quedan ocupando nada). ✔
- **Operaciones:** retenido no se envía a cocina; notas siguen a la cantidad; solo se unen mesas libres; anular mesa unida libera todas. ✔
- **Módulos "pronto"** (stock, recetas, compras, DIAN, impresoras): abren sin romperse. ✔

---

## 📌 Puntos menores anotados (no urgentes, para una próxima vuelta)

- Un empleado eliminado por el admin podría entrar **sin internet** con su PIN previo (offline). Online queda bloqueado. Se resuelve del todo con el Worker de acceso (Camino B).
- Con dos cajeros registrando movimientos **al mismo tiempo** en la misma caja, el segundo puede pisar al primero (last-write-wins). Poco común; se puede blindar con merge por movimiento.
- El importador cuenta como "2 nuevos" dos filas con el mismo nombre nuevo (crea 1). Solo afecta el conteo de la previa, no los datos.
- Vaciar por completo una comanda **unida** deja las mesas ocupadas hasta que se cancele (por diseño de la unión).
- Impuestos DIAN, stock/kardex y pasarela de pagos siguen pendientes de sus fases.

---
*Auditoría completa con 152 pruebas automáticas internas + revisión de todos los módulos. Todo en verde tras las correcciones.*
