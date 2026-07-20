/**
 * Genera el SQL de carga de los 64 estudiantes a partir de data/estudiantes.json.
 *
 *   node scripts/seed.js   ->  supabase/02-datos.sql
 *
 * El archivo resultante lleva cedulas y celulares reales, asi que esta en
 * .gitignore: se ejecuta una vez en el SQL Editor de Supabase y no se versiona.
 */
const fs = require('fs');
const path = require('path');

const RAIZ = path.join(__dirname, '..');

/** Escapa una cadena para un literal SQL. */
function lit(v) {
  if (v === null || v === undefined || String(v).trim() === '') return 'null';
  return "'" + String(v).trim().replace(/'/g, "''") + "'";
}

const estudiantes = JSON.parse(
  fs.readFileSync(path.join(RAIZ, 'data', 'estudiantes.json'), 'utf8')
);

const filas = estudiantes.map((e) => {
  const id = parseInt(e.id, 10);
  if (!Number.isInteger(id)) {
    console.error('Id no numerico en el registro: ' + JSON.stringify(e));
    process.exit(1);
  }
  const gpa = (e.gpa === null || e.gpa === undefined || e.gpa === '') ? 'null' : Number(e.gpa);
  return '  (' + [
    id,
    lit(e.apellidos),
    lit(e.nombres),
    lit(e.codigo),
    lit(e.cedula),
    lit(e.correoInst),
    lit(e.correoPers),
    lit(e.celular),
    gpa
  ].join(', ') + ')';
});

const sql = [
  '-- ============================================================',
  '--  Carga de estudiantes (' + filas.length + ' registros)',
  '--  Generado por scripts/seed.js — no editar a mano.',
  '--  CONTIENE DATOS PERSONALES: no versionar, no compartir.',
  '--  Ejecutar despues de 01-esquema.sql.',
  '-- ============================================================',
  '',
  'insert into public.estudiantes',
  '  (id, apellidos, nombres, codigo, cedula, correo_inst, correo_pers, celular, gpa)',
  'values',
  filas.join(',\n'),
  'on conflict (id) do update set',
  '  apellidos   = excluded.apellidos,',
  '  nombres     = excluded.nombres,',
  '  codigo      = excluded.codigo,',
  '  cedula      = excluded.cedula,',
  '  correo_inst = excluded.correo_inst,',
  '  correo_pers = excluded.correo_pers,',
  '  celular     = excluded.celular,',
  '  gpa         = excluded.gpa;',
  '',
  '-- Comprobacion: debe devolver ' + filas.length,
  'select count(*) as total from public.estudiantes;',
  ''
].join('\n');

const salida = path.join(RAIZ, 'supabase', '02-datos.sql');
fs.mkdirSync(path.dirname(salida), { recursive: true });
fs.writeFileSync(salida, sql);

console.log('registros : ' + filas.length);
console.log('salida    : ' + path.relative(RAIZ, salida));
console.log('aviso     : contiene datos personales, esta en .gitignore');
