// ============================================================
//  INGRESO EN LÍNEA - programa que vive dentro de Google Sheets
//  Recibe las cédulas que escanean los celulares, las busca en
//  la hoja "Invitados" y escribe el estado y la hora.
//  Todos los celulares ven la misma hoja: así nadie entra dos veces.
// ============================================================

// ---------- CONFIGURACIÓN (puede cambiarla) ----------
const CLAVE = 'evento2026';     // escriba esta MISMA clave en la app
const HOJA  = 'Invitados';      // nombre de la pestaña con la lista
const ZONA  = 'America/Bogota'; // hora de Colombia

// ---------- Punto de entrada: la app llama aquí ----------
function doGet(e) {
  const p = (e && e.parameter) || {};
  let r;
  try {
    if (p.clave !== CLAVE)            r = { ok: false, error: 'Clave incorrecta' };
    else if (p.accion === 'resumen')  r = conBloqueo_(() => resumenDe_(tabla_()));
    else if (p.accion === 'registrar') r = conBloqueo_(() => registrar_(p, false));
    else if (p.accion === 'autorizar') r = conBloqueo_(() => registrar_(p, true));
    else r = { ok: true, mensaje: 'Conexión correcta' };
  } catch (err) {
    r = { ok: false, error: String(err.message || err) };
  }
  return ContentService.createTextOutput(JSON.stringify(r))
    .setMimeType(ContentService.MimeType.JSON);
}

// Evita que dos celulares escriban la misma fila al mismo tiempo
function conBloqueo_(fn) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try { return fn(); } finally { lock.releaseLock(); }
}

// ---------- Utilidades de texto ----------
function norm_(s) {
  return String(s == null ? '' : s).normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '').toLowerCase().replace(/[\s_.\-º°#]/g, '');
}
function soloNum_(s) {
  return String(s == null ? '' : s).replace(/\D/g, '').replace(/^0+/, '');
}
function texto_(v) {
  if (v instanceof Date) return Utilities.formatDate(v, ZONA, 'HH:mm:ss');
  return String(v == null ? '' : v);
}
const RE_CED = /^(cedula|cc|documento|numerodedocumento|numerodocumento|identificacion|numerodeidentificacion|numeroidentificacion|nodocumento|id)$/;

// ---------- Leer la hoja y ubicar las columnas ----------
function tabla_() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  const sh = ss.getSheetByName(HOJA) || ss.getSheets()[0];
  const datos = sh.getDataRange().getValues();
  let fe = -1;
  for (let r = 0; r < Math.min(25, datos.length); r++) {
    if (datos[r].some(c => RE_CED.test(norm_(c)))) { fe = r; break; }
  }
  if (fe < 0) throw new Error('No se encontró una columna llamada "Cedula" en la hoja');
  const enc = datos[fe].map(norm_);
  const col = re => enc.findIndex(h => re.test(h));
  const c = {
    ced: col(RE_CED),
    nom: col(/^nombres?$|^nombrecompleto$/),
    ape: col(/^apellidos?$/),
    est: col(/^estado$/),
    hc:  col(/^horaconfirmacion$/),
    hi:  col(/^horaingreso$/),
    pu:  col(/^puerta$/)
  };
  // Si faltan columnas de control, se agregan al final
  let ancho = datos[fe].length;
  [['est', 'Estado'], ['hc', 'Hora_confirmacion'], ['hi', 'Hora_ingreso'], ['pu', 'Puerta']]
    .forEach(([k, titulo]) => {
      if (c[k] < 0) {
        sh.getRange(fe + 1, ancho + 1).setValue(titulo).setFontWeight('bold');
        c[k] = ancho; ancho++;
      }
    });
  return { sh, datos, fe, c };
}

function estadoDe_(t, fila) {
  const e = norm_(t.datos[fila][t.c.est]);
  return e.startsWith('ingres') ? 'Ingresó' : e.startsWith('confirm') ? 'Confirmado' : 'Pendiente';
}

function resumenDe_(t) {
  const r = { ok: true, total: 0, pendientes: 0, confirmados: 0, ingresaron: 0 };
  for (let f = t.fe + 1; f < t.datos.length; f++) {
    if (!soloNum_(t.datos[f][t.c.ced])) continue;
    r.total++;
    const e = estadoDe_(t, f);
    if (e === 'Ingresó') r.ingresaron++;
    else if (e === 'Confirmado') r.confirmados++;
    else r.pendientes++;
  }
  return r;
}

// Busca la cédula entre los grupos de números leídos del código.
// Cédula amarilla (PDF417): el número viene con ceros a la izquierda (10 dígitos).
function buscar_(t, numeros) {
  const grupos = String(numeros || '').split(',').map(s => s.trim()).filter(Boolean);
  let mejor = -1, mejorId = '';
  for (let f = t.fe + 1; f < t.datos.length; f++) {
    const id = soloNum_(t.datos[f][t.c.ced]);
    if (!id) continue;
    const conCeros = id.padStart(10, '0');
    const coincide = grupos.some(g => g === id || soloNum_(g) === id || g.endsWith(conCeros));
    if (coincide && id.length > mejorId.length) { mejor = f; mejorId = id; }
  }
  return { fila: mejor, id: mejorId };
}

// ---------- Reglas de ingreso ----------
function registrar_(p, forzar) {
  const t = tabla_();
  const { fila, id } = buscar_(t, p.numeros);
  let r;
  if (fila < 0) {
    r = { tipo: 'error', titulo: 'No está en la lista',
          quien: p.leido ? 'Cédula ' + p.leido : 'Código no reconocido',
          detalle: 'No puede ingresar.' };
    return Object.assign(resumenDe_(t), r);
  }
  const fila1 = t.datos[fila];
  const nombre = [t.c.nom >= 0 ? fila1[t.c.nom] : '', t.c.ape >= 0 ? fila1[t.c.ape] : '']
    .join(' ').trim() || 'Invitado sin nombre';
  const hora = Utilities.formatDate(new Date(), ZONA, 'HH:mm:ss');
  const puerta = p.puerta || '';
  const poner = (k, v) => {
    t.sh.getRange(fila + 1, t.c[k] + 1).setNumberFormat('@').setValue(v);
    fila1[t.c[k]] = v;
  };
  const estado = estadoDe_(t, fila);

  if (p.modo === 'confirmar') {
    if (estado === 'Pendiente') {
      poner('est', 'Confirmado'); poner('hc', hora); poner('pu', puerta);
      r = { tipo: 'ok', titulo: 'Confirmado', quien: nombre,
            detalle: 'Cédula ' + id + '. Ahora debe pasar al paso 2 (Ingreso).' };
    } else if (estado === 'Confirmado') {
      r = { tipo: 'aviso', titulo: 'Ya estaba confirmado', quien: nombre,
            detalle: 'Confirmado a las ' + texto_(fila1[t.c.hc]) + '. Envíelo al ingreso.' };
    } else {
      r = { tipo: 'aviso', titulo: 'Ya ingresó', quien: nombre,
            detalle: 'Entró a las ' + texto_(fila1[t.c.hi]) + ' por ' + (texto_(fila1[t.c.pu]) || 'la entrada') + '.' };
    }
  } else {
    if (estado === 'Confirmado' || (estado === 'Pendiente' && forzar)) {
      if (estado === 'Pendiente') poner('hc', hora);
      poner('est', 'Ingresó'); poner('hi', hora); poner('pu', puerta);
      r = { tipo: 'ok', titulo: 'Puede ingresar', quien: nombre,
            detalle: 'Cédula ' + id + '. Ingreso a las ' + hora + (forzar ? ' (autorizado manualmente).' : '.') };
    } else if (estado === 'Pendiente') {
      r = { tipo: 'aviso', titulo: 'No ha confirmado', quien: nombre,
            detalle: 'Está en la lista pero no pasó por el paso 1.', puedeAutorizar: true };
    } else {
      r = { tipo: 'error', titulo: 'Ya ingresó', quien: nombre,
            detalle: 'Entró a las ' + texto_(fila1[t.c.hi]) + ' por ' + (texto_(fila1[t.c.pu]) || 'la entrada') +
                     '. No se permite un segundo ingreso.' };
    }
  }
  return Object.assign(resumenDe_(t), r);
}

// ---------- Para probar desde el editor (botón Ejecutar) ----------
function probar() {
  const t = tabla_();
  Logger.log(JSON.stringify(resumenDe_(t)));
}
