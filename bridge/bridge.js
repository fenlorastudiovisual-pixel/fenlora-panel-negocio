// ════════════════════════════════════════════════════════════════════
// FENLORA · PRINT BRIDGE
// Corre en el portátil Windows de dulcecafe, conectado por USB a la
// impresora térmica POS-5890U-L. Recibe tickets desde el navegador
// (pos.fenloravisual.com/dulcecafe) en http://localhost:4321/imprimir
// y los manda en crudo (ESC/POS) directo al puerto de la impresora.
//
// No usa módulos nativos (nada de compilar con Visual Studio / Python):
// escribe un archivo temporal y lo copia al puerto con el comando
// "copy /b" de Windows, que es la forma más simple y confiable de
// mandar bytes crudos a una impresora térmica en Windows.
// ════════════════════════════════════════════════════════════════════

const express = require('express');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { exec } = require('child_process');

const PORT = 4321;

// ⚠️ AJUSTA ESTO: abre "Impresoras y escáneres" en Windows, entra a las
// propiedades de la impresora (ej. "POS-58" o como se llame) y mira la
// pestaña "Puertos". Ahí vas a ver algo como USB001, USB002, etc.
const PUERTO_IMPRESORA = process.env.FENLORA_PUERTO || 'USB001';

const app = express();
app.use(express.json({ limit: '1mb' }));

// Permite que el navegador llame a este servicio local sin bloqueo CORS
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

// ── Comandos ESC/POS básicos ──
const ESC = '\x1B', GS = '\x1D';
const INIT = ESC + '@';
const ALIGN = { left: ESC + 'a' + '\x00', center: ESC + 'a' + '\x01', right: ESC + 'a' + '\x02' };
const BOLD_ON = ESC + 'E' + '\x01', BOLD_OFF = ESC + 'E' + '\x00';
const DOUBLE_ON = GS + '!' + '\x11', DOUBLE_OFF = GS + '!' + '\x00';
const CUT = GS + 'V' + '\x01';
const ANCHO = 32; // caracteres por línea en 58mm, fuente normal

// Muchas de estas impresoras clon no traen bien configurada la página de
// códigos para tildes/ñ. Para no arriesgarnos a que salga texto corrido,
// quitamos acentos. Si al probar ves que tu impresora sí soporta tildes,
// avísame y quitamos esta limpieza.
function limpio(s) {
  return String(s == null ? '' : s)
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/[^\x00-\x7E]/g, '?');
}
function linea(izq, der) {
  izq = limpio(izq); der = limpio(der);
  const espacio = Math.max(1, ANCHO - izq.length - der.length);
  return izq + ' '.repeat(espacio) + der + '\n';
}
function centrado(s) { return limpio(s) + '\n'; }
function separador() { return '-'.repeat(ANCHO) + '\n'; }

function construirTicket(d) {
  let t = INIT;
  t += ALIGN.center + BOLD_ON + DOUBLE_ON + centrado(d.titulo || 'FENLORA') + DOUBLE_OFF + BOLD_OFF;
  if (d.subtitulo) t += centrado(d.subtitulo);
  t += ALIGN.left + separador();
  if (d.cliente) t += centrado('Cliente: ' + d.cliente);
  if (d.mesero) t += centrado('Mesero: ' + d.mesero);
  if (d.fecha) t += centrado('Fecha: ' + d.fecha);
  if (d.hora) t += centrado('Hora: ' + d.hora);
  if (d.orden) t += centrado('Orden: ' + d.orden);
  t += separador();
  (d.items || []).forEach(it => {
    t += linea(`${it.qty || ''} ${it.nombre || ''}`.trim(), it.importe || '');
    if (it.nota) t += centrado('  > ' + it.nota);
  });
  t += separador();
  if (!d.esComanda && d.total) t += BOLD_ON + linea('TOTAL', d.total) + BOLD_OFF;
  if (d.recibido) t += linea('Recibido', d.recibido);
  if (d.cambio) t += linea('Cambio', d.cambio);
  t += ALIGN.center + centrado(d.pie || 'FENLORA CLOUD');
  t += '\n\n\n' + CUT;
  return Buffer.from(t, 'binary');
}

function imprimir(buf, cb) {
  const tmp = path.join(os.tmpdir(), 'fenlora_ticket_' + Date.now() + '.prn');
  fs.writeFile(tmp, buf, (err) => {
    if (err) return cb(err);
    exec(`copy /b "${tmp}" "${PUERTO_IMPRESORA}"`, (err2) => {
      fs.unlink(tmp, () => {});
      cb(err2 || null);
    });
  });
}

app.post('/imprimir', (req, res) => {
  try {
    const buf = construirTicket(req.body || {});
    imprimir(buf, (err) => {
      if (err) return res.status(500).json({ ok: false, error: String(err) });
      res.json({ ok: true });
    });
  } catch (e) {
    res.status(500).json({ ok: false, error: String((e && e.message) || e) });
  }
});

app.get('/ping', (req, res) => res.json({ ok: true, puerto: PUERTO_IMPRESORA }));

app.listen(PORT, '127.0.0.1', () => {
  console.log('🖨️  Fenlora Print Bridge escuchando en http://localhost:' + PORT);
  console.log('    Puerto de impresora configurado: ' + PUERTO_IMPRESORA);
  console.log('    Deja esta ventana abierta mientras uses el POS.');
});
