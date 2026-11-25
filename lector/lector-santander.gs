/**
 * Lector de avisos Santander → Tablero (Consumos)
 * Corre en tu Gmail personal. Solo LEE los mails de Santander y manda
 * fecha, comercio, importe y tarjeta al tablero. No borra ni mueve mails.
 *
 * Instalación (una sola vez):
 * 1. En el tablero: Ajustes → Lector de mails Santander → "Mostrar clave" → copiar.
 * 2. Acá: Configuración del proyecto (engranaje) → Propiedades del script →
 *    Agregar propiedad:  TOKEN  =  (pegar la clave)  → Guardar.
 * 3. Elegir la función "configurar" arriba y tocar "Ejecutar". Autorizar con tu cuenta.
 *    Eso carga los últimos 90 días y deja el lector corriendo solo cada 15 minutos.
 */

const SB_URL = 'https://sipgrhcxignspvkeqgec.supabase.co';
const SB_KEY = 'sb_publishable_kSznWqJh-iaCZC5wCaHYiQ_mSbXwdF4'; // clave pública del tablero
const REMITENTE = 'mails.santander.com.ar';
const ETIQUETA = 'Tablero/Santander';
const TZ = 'America/Argentina/Buenos_Aires';

function configurar() {
  if (!PropertiesService.getScriptProperties().getProperty('TOKEN')) {
    throw new Error('Falta la propiedad TOKEN (ver instrucciones arriba).');
  }
  ScriptApp.getProjectTriggers()
    .filter(t => t.getHandlerFunction() === 'leerSantander')
    .forEach(t => ScriptApp.deleteTrigger(t));
  ScriptApp.newTrigger('leerSantander').timeBased().everyMinutes(15).create();
  const n = leerSantander(90);
  console.log('Listo. Consumos nuevos cargados: ' + n + '. El lector queda corriendo cada 15 minutos.');
}

function leerSantander(dias) {
  dias = (typeof dias === 'number') ? dias : 3;
  const token = PropertiesService.getScriptProperties().getProperty('TOKEN');
  if (!token) throw new Error('Falta la propiedad TOKEN.');
  const etiqueta = GmailApp.getUserLabelByName(ETIQUETA) || GmailApp.createLabel(ETIQUETA);
  let total = 0;
  for (let start = 0; start < 2000; start += 100) {
    const hilos = GmailApp.search('from:' + REMITENTE + ' newer_than:' + dias + 'd', start, 100);
    if (!hilos.length) break;
    const items = [];
    hilos.forEach(h => h.getMessages().forEach(m => {
      if (m.getFrom().indexOf(REMITENTE) < 0) return;
      const it = interpretar(m);
      if (it) items.push(it);
    }));
    if (items.length) total += enviar(token, items);
    hilos.forEach(h => h.addLabel(etiqueta));
    if (hilos.length < 100) break;
  }
  return total;
}

function enviar(token, items) {
  const r = UrlFetchApp.fetch(SB_URL + '/rest/v1/rpc/ingest_consumos', {
    method: 'post',
    contentType: 'application/json',
    headers: { apikey: SB_KEY },
    payload: JSON.stringify({ p_token: token, p_items: items }),
    muteHttpExceptions: true
  });
  if (r.getResponseCode() >= 300) throw new Error('El tablero rechazó la carga: ' + r.getContentText());
  return parseInt(r.getContentText(), 10) || 0;
}

function interpretar(m) {
  const asunto = m.getSubject() || '';
  let txt = m.getPlainBody() || '';
  if (!txt.trim()) txt = m.getBody().replace(/<br\s*\/?>/gi, '\n').replace(/<\/(p|div|tr|td|li|h\d)>/gi, '\n').replace(/<[^>]+>/g, ' ');
  txt = txt.replace(/&nbsp;/g, ' ').replace(/\r/g, '').replace(/[ \t]+/g, ' ');
  const L = txt.split('\n').map(s => s.trim()).filter(Boolean);
  const todo = asunto + '\n' + L.join('\n');

  const valor = (et) => {
    const re = new RegExp('^' + et + '\\s*:?\\s*(.*)$', 'i');
    for (let i = 0; i < L.length; i++) {
      const mm = L[i].match(re);
      if (mm) return (mm[1] || L[i + 1] || '').trim();
    }
    return '';
  };

  // Tarjeta
  const tj = todo.match(/Tarjeta\s+(.+?)\s+terminada\s+en\s+(\d{4})/i);
  let tipo = 'otro', tarjeta = '', ult4 = '';
  if (tj) {
    tarjeta = tj[1].replace(/^Santander\s+/i, '').trim();
    ult4 = tj[2];
    tipo = /d[eé]bito/i.test(tarjeta) ? 'debito' : 'credito';
  } else if (/transfer/i.test(todo)) tipo = 'transferencia';
  else if (/d[eé]bito/i.test(todo)) tipo = 'debito';
  const cta = todo.match(/cuenta[^\n]*?terminada\s+en\s+(\d{3,4})/i);
  if (!ult4 && cta) ult4 = cta[1];

  // Monto y moneda
  let montoTxt = valor('Monto') || valor('Importe');
  if (!/\d/.test(montoTxt)) montoTxt = (asunto.match(/(U\$S|US\$|USD|\$)\s?[\d.,]+/) || [''])[0];
  const monto = numero(montoTxt);
  if (!monto) return null; // no es un movimiento (ej. promociones)
  const moneda = /U\$S|US\$|USD|d[oó]lar/i.test(montoTxt) ? 'USD' : 'ARS';

  // Comercio / destinatario
  let comercio = '', detalle = '';
  const ci = L.findIndex(x => /^(comercio|destinatario|para)\s*:?$/i.test(x));
  if (ci >= 0) {
    let fi = L.findIndex((x, i) => i > ci && /^(fecha|hora|cuotas|monto|importe|cuenta|cbu|alias)\b/i.test(x));
    if (fi < 0) fi = ci + 3;
    const partes = L.slice(ci + 1, fi);
    comercio = partes[0] || '';
    detalle = partes.slice(1).join(' ');
  } else {
    comercio = valor('Comercio') || valor('Destinatario');
  }

  // Fecha y hora
  const f = (valor('Fecha').match(/(\d{2})\/(\d{2})\/(\d{4})/) || []);
  const fecha = f.length ? f[3] + '-' + f[2] + '-' + f[1] : Utilities.formatDate(m.getDate(), TZ, 'yyyy-MM-dd');
  const hora = (valor('Hora').match(/\d{1,2}:\d{2}/) || [])[0] || Utilities.formatDate(m.getDate(), TZ, 'HH:mm');
  const cuotas = parseInt(valor('Cuotas'), 10) || null;

  return {
    msg_id: m.getId(), fecha: fecha, hora: hora, tipo: tipo, tarjeta: tarjeta, ultimos4: ult4,
    comercio: comercio, comercio_detalle: detalle, monto: monto, moneda: moneda, cuotas: cuotas,
    asunto: asunto.slice(0, 200)
  };
}

function numero(s) {
  s = String(s || '').replace(/[^\d.,-]/g, '');
  if (!s) return 0;
  if (s.indexOf(',') >= 0) s = s.replace(/\./g, '').replace(',', '.');
  else if (/^\d{1,3}(\.\d{3})+$/.test(s)) s = s.replace(/\./g, '');
  return Math.round((parseFloat(s) || 0) * 100) / 100;
}

/** Prueba manual: muestra cómo interpreta los últimos 5 avisos, sin cargar nada. */
function probar() {
  GmailApp.search('from:' + REMITENTE, 0, 5).forEach(h => h.getMessages().forEach(m => console.log(JSON.stringify(interpretar(m)))));
}
