/**
 * Genera el HTML autonomo del tablero a partir de la plantilla y los datos.
 *
 *   node scripts/build.js publico   -> docs/index.html  (cedula y celular enmascarados)
 *   node scripts/build.js interno   -> dist/index.html  (datos completos)
 *
 * En un sitio estatico no hay servidor: TODO lo que la pagina puede mostrar o
 * exportar viaja en el codigo fuente. Por eso la version publica no "oculta"
 * los datos sensibles, los reemplaza antes de escribir el archivo.
 */
const fs = require('fs');
const path = require('path');

const RAIZ = path.join(__dirname, '..');
const modo = (process.argv[2] || 'publico').toLowerCase();

const MODOS = {
  // La version publica (GitHub Pages) EXIGE tabla: los datos no se incrustan,
  // llegan tras iniciar sesion. Ver la verificacion mas abajo.
  publico:  { salida: ['docs', 'index.html'],    documento: true,  exigeRemoto: true },
  // Uso local / Docker: datos completos incrustados, tras las tablas gitignore.
  interno:  { salida: ['dist', 'index.html'],    documento: true,  exigeRemoto: false },
  // Un artifact de Claude se envuelve solo: se entrega sin <html>/<head>/<body>.
  artifact: { salida: ['dist', 'artifact.html'], documento: false, exigeRemoto: false }
};

if (!MODOS[modo]) {
  console.error('Modo no valido: "' + modo + '". Use: ' + Object.keys(MODOS).join(', ') + '.');
  process.exit(1);
}

const cfg = MODOS[modo];

const estudiantes = JSON.parse(
  fs.readFileSync(path.join(RAIZ, 'data', 'estudiantes.json'), 'utf8')
);

const plantilla = fs.readFileSync(path.join(RAIZ, 'src', 'plantilla.html'), 'utf8');
const MARCA = '/*__DATA__*/[]';

if (!plantilla.includes(MARCA)) {
  console.error('La plantilla no contiene el marcador ' + MARCA);
  process.exit(1);
}

// Configuracion de Supabase. Sin url/anonKey la pagina queda en modo local.
const MARCA_CFG = "/*__CONFIG__*/{ url: '', anonKey: '' }";
const rutaCfg = path.join(RAIZ, 'src', 'config.json');
let conexion = { url: '', anonKey: '' };
if (fs.existsSync(rutaCfg)) {
  const bruto = JSON.parse(fs.readFileSync(rutaCfg, 'utf8'));
  conexion = { url: (bruto.url || '').replace(/\/+$/, ''), anonKey: bruto.anonKey || '' };
}
const remoto = Boolean(conexion.url && conexion.anonKey);

// La version publica solo puede construirse con tabla configurada. Asi es
// imposible generar un docs/index.html con datos personales incrustados.
if (cfg.exigeRemoto && !remoto) {
  console.error('ABORTADO: el modo "publico" exige configurar src/config.json con');
  console.error('la URL y la anon key de Supabase. Sin eso el HTML incrustaria los');
  console.error('datos de los 64 postulantes sin login. Configura la tabla y reintenta.');
  process.exit(1);
}

// Con tabla configurada el HTML NO lleva datos: llegan tras iniciar sesion.
// Si se incrustaran, bastaria ver el codigo fuente para leerlos sin entrar.
const incrustados = remoto ? [] : estudiantes;

let html = plantilla.replace(MARCA, JSON.stringify(incrustados, null, 1));

if (!plantilla.includes(MARCA_CFG)) {
  console.error('La plantilla no contiene el marcador de configuracion.');
  process.exit(1);
}
html = html.replace(MARCA_CFG, JSON.stringify(conexion));

if (html.includes('__DATA__') || html.includes('__CONFIG__')) {
  console.error('Quedo un marcador sin reemplazar.');
  process.exit(1);
}

// Una contrasena jamas debe acabar dentro de un build. Se cubren las variantes
// en ingles y espanol; se descartan las apariciones legitimas del atributo/param.
const sospechoso = html
  .replace(/password:\s*clave/g, '')
  .replace(/autocomplete="(current-password|username)"/g, '')
  .replace(/id="acceso-clave"|#acceso-clave/g, '');
if (/(password|contrase(?:n|ñ|&ntilde;)a|clave)\s*[:=]\s*['"][^'"]{3,}['"]/i.test(sospechoso)) {
  console.error('ABORTADO: parece haber una contrasena escrita en el HTML generado.');
  process.exit(1);
}

// Formato artifact: la plataforma aporta el esqueleto del documento
if (!cfg.documento) {
  // Se conserva <title> + <style> (van dentro del <head> que aporta la
  // plataforma) y el contenido interior de <body>; se descartan las etiquetas
  // del documento, que el wrapper del artifact ya provee.
  const iniCabeza = html.indexOf('<title>');
  const finCabeza = html.indexOf('</head>');
  const iniCuerpo = html.indexOf('<body>');
  const finCuerpo = html.lastIndexOf('</body>');
  if ([iniCabeza, finCabeza, iniCuerpo, finCuerpo].some((i) => i < 0)) {
    console.error('No pude recortar el documento para el formato artifact.');
    process.exit(1);
  }
  const cabeza = html.slice(iniCabeza, finCabeza).trim();
  const cuerpo = html.slice(iniCuerpo + '<body>'.length, finCuerpo).trim();
  html = cabeza + '\n\n' + cuerpo + '\n';
  // Delimitado: sin esto "<head" tambien coincidiria con "<header>"
  if (/<!DOCTYPE|<\/?(html|head|body)[\s>]/i.test(html)) {
    console.error('ABORTADO: quedaron etiquetas de documento en el formato artifact.');
    process.exit(1);
  }
}

const salida = path.join(RAIZ, ...cfg.salida);

fs.mkdirSync(path.dirname(salida), { recursive: true });
fs.writeFileSync(salida, html);

// Con tabla configurada, NINGUN dato personal puede viajar en el HTML.
// Se cubren todos los campos, no solo algunos.
if (remoto) {
  const campos = ['apellidos', 'nombres', 'codigo', 'cedula', 'correoInst', 'correoPers', 'celular'];
  const filtrados = estudiantes.filter(
    (e) => campos.some((k) => e[k] && html.includes(String(e[k])))
  );
  if (filtrados.length) {
    console.error('ABORTADO: ' + filtrados.length + ' registros quedaron incrustados pese a usar tabla.');
    process.exit(1);
  }
}

console.log('modo        : ' + modo);
console.log('acceso      : ' + (remoto ? 'con login (datos desde la tabla)' : 'SIN login (datos en el HTML)'));
console.log('estudiantes : ' + incrustados.length);
console.log('salida      : ' + path.relative(RAIZ, salida));
console.log('tamano      : ' + (html.length / 1024).toFixed(1) + ' KB');
if (remoto) console.log('verificado  : ningun dato personal en el HTML; llegan tras iniciar sesion');
if (!remoto) console.log('nota        : datos incrustados — solo para uso local / Docker, no publicar');
