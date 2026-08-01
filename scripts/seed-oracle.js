/**
 * Genera el SQL de carga de los 64 estudiantes para Oracle.
 *
 *   node scripts/seed-oracle.js   ->  oracle/02-datos-oracle.sql
 *
 * El archivo resultante lleva cedulas y celulares reales, asi que esta en
 * .gitignore: se ejecuta una vez en SQL Developer (F5) y no se versiona.
 */
const fs = require('fs');
const path = require('path');

const RAIZ = path.join(__dirname, '..');

/** Literal SQL de texto: escapa comillas simples; vacio -> NULL. */
function lit(v) {
  if (v === null || v === undefined || String(v).trim() === '') return 'NULL';
  return "'" + String(v).trim().replace(/'/g, "''") + "'";
}

/** Literal numerico: numero con punto decimal; vacio/no numerico -> NULL. */
function num(v) {
  if (v === null || v === undefined || String(v).trim() === '') return 'NULL';
  const n = Number(v);
  return isNaN(n) ? 'NULL' : String(n);
}

const estudiantes = JSON.parse(
  fs.readFileSync(path.join(RAIZ, 'data', 'estudiantes.json'), 'utf8')
);

const inserts = estudiantes.map((e) => {
  const id = parseInt(e.id, 10);
  if (!Number.isInteger(id)) {
    console.error('Id no numerico: ' + JSON.stringify(e));
    process.exit(1);
  }
  return 'INSERT INTO int_estudiantes (id, apellidos, nombres, codigo, cedula, correo_inst, correo_pers, celular, gpa, creditos, examen, pensum, discapacidad, embarazada, hijos, estado_civil) VALUES (' +
    [
      id,
      lit(e.apellidos), lit(e.nombres), lit(e.codigo), lit(e.cedula),
      lit(e.correoInst), lit(e.correoPers), lit(e.celular),
      num(e.gpa), num(e.creditos), num(e.examen),
      lit(e.pensum), lit(e.discapacidad), lit(e.embarazada),
      num(e.hijos), lit(e.estadoCivil)
    ].join(', ') + ');';
});

const sql = [
  '-- ============================================================',
  '--  Carga de estudiantes en Oracle (' + inserts.length + ' registros)',
  '--  Generado por scripts/seed-oracle.js — no editar a mano.',
  '--  CONTIENE DATOS PERSONALES: no versionar, no compartir.',
  '--  Ejecutar con Run Script (F5) DESPUES de 01-esquema-oracle.sql.',
  '--  Si ya habia datos y quieres recargar, descomenta la linea DELETE.',
  '-- ============================================================',
  '',
  '-- DELETE FROM int_estudiantes;',
  '',
  ...inserts,
  '',
  'COMMIT;',
  '',
  '-- Comprobacion: debe devolver ' + inserts.length,
  'SELECT COUNT(*) AS total FROM int_estudiantes;',
  ''
].join('\n');

const salida = path.join(RAIZ, 'oracle', '02-datos-oracle.sql');
fs.mkdirSync(path.dirname(salida), { recursive: true });
fs.writeFileSync(salida, sql);

console.log('registros : ' + inserts.length);
console.log('salida    : ' + path.relative(RAIZ, salida));
console.log('aviso     : contiene datos personales, esta en .gitignore');
