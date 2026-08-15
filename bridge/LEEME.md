# Fenlora Print Bridge — instalación en el portátil de dulcecafe

Esto conecta tu POS (en el navegador) con la impresora térmica **POS-5890U-L** por USB.

## 1. Instalar Node.js (una sola vez)
Si el portátil no tiene Node.js: descárgalo de https://nodejs.org (versión LTS) e instálalo con las opciones por defecto.

## 2. Conectar e instalar la impresora
1. Conecta la POS-5890U-L por USB al portátil.
2. Windows debería detectarla sola. Si no aparece, ve a **Configuración → Bluetooth y dispositivos → Impresoras y escáneres → Agregar dispositivo**, y si no la encuentra, instala el driver genérico **"Generic / Text Only"** (ese sirve para mandar texto crudo, que es justo lo que necesitamos).
3. Ya instalada, entra a **Impresoras y escáneres**, clic en la impresora → **Propiedades de impresora** → pestaña **Puertos**.
4. Anota el puerto que tiene marcado (normalmente algo como `USB001`).

## 3. Instalar el bridge
1. Copia esta carpeta completa (`bridge.js`, `package.json`, `iniciar.bat`) a un lugar fijo del portátil, ej. `C:\Fenlora\bridge`.
2. Abre esa carpeta, mantén Shift + clic derecho → **Abrir ventana de PowerShell aquí** (o `cmd`).
3. Corre:
   ```
   npm install
   ```
4. Si el puerto que anotaste en el paso 2.4 **no** es `USB001`, edita `bridge.js` y cambia esta línea al puerto real:
   ```js
   const PUERTO_IMPRESORA = process.env.FENLORA_PUERTO || 'USB001';
   ```

## 4. Arrancarlo
Doble clic en `iniciar.bat`. Debe quedar una ventana negra abierta diciendo:
```
🖨️  Fenlora Print Bridge escuchando en http://localhost:4321
```
**Esa ventana debe quedar abierta** mientras uses el POS (puedes minimizarla, no cerrarla).

## 5. Probar
Con el bridge corriendo, abre esta URL en el navegador del mismo portátil:
```
http://localhost:4321/ping
```
Debe responder `{"ok":true,...}`. Si responde eso, entra a `pos.fenloravisual.com/dulcecafe`, manda una comanda de prueba y dale **Imprimir** — debería salir el ticket en la impresora.

## Notas
- Si algún día quieres que arranque solo con Windows, se puede poner `iniciar.bat` en la carpeta de inicio de Windows (`shell:startup`) — dime y te explico ese paso también.
- Esto solo imprime en el equipo donde está corriendo el bridge. Si mañana quieres imprimir también desde el celular del mesero, necesitamos otra solución (ese caso lo vemos aparte).
- Ya dejé conectados en tu `index.html` los botones de: Imprimir/Reimprimir comanda, precuenta, envío a cocina (por área) y reimprimir factura.
