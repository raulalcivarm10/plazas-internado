-- ============================================================
--  Endpoints REST del tablero (ORDS) — Oracle
--  Ejecutar con Run Script (F5) DESPUES de 03-auth.sql.
--
--  Expone bajo  .../ords/internado/plazas/ :
--    POST login        {email, clave}      -> {token, email}
--    GET  yo           (X-Token)           -> {email} | 401
--    GET  sedes        (X-Token)           -> {items:[...]}
--    GET  estudiantes  (X-Token)           -> {items:[...]}
--    POST asignar      {id, sede_id|null}  -> {ok} | 409 cupo | 423 finalizado
--    POST bloquear     {id, bloqueado}     -> {ok} | 423 finalizado
--    POST vaciar       (X-Token)           -> {ok, liberadas} | 423 finalizado
--    GET  config       (X-Token)           -> {finalizado}
--    POST finalizar    {finalizado}        -> {ok, finalizado}
--    POST salir        (X-Token)           -> {ok}
--
--  Sin token valido, sedes/estudiantes devuelven vacio y las
--  escrituras 401. Con el periodo finalizado, las escrituras 423.
-- ============================================================

BEGIN
  ORDS.ENABLE_SCHEMA(
    p_enabled             => TRUE,
    p_schema              => 'QUADRA',
    p_url_mapping_type    => 'BASE_PATH',
    p_url_mapping_pattern => 'internado',
    p_auto_rest_auth      => FALSE
  );

  ORDS.DEFINE_MODULE(
    p_module_name    => 'plazas',
    p_base_path      => '/plazas/',
    p_items_per_page => 1000,
    p_status         => 'PUBLISHED'
  );

  ------------------------------------------------------------------ login
  ORDS.DEFINE_TEMPLATE(p_module_name => 'plazas', p_pattern => 'login');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'plazas', p_pattern => 'login', p_method => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'[
DECLARE
  v_token VARCHAR2(64);
BEGIN
  v_token := int_auth.login(:email, :clave);
  HTP.p('{"token":"' || v_token || '","email":"' || LOWER(TRIM(:email)) || '"}');
EXCEPTION WHEN OTHERS THEN
  :status_code := 401;
  HTP.p('{"error":"Correo o contrasena incorrectos"}');
END;]'
  );

  ------------------------------------------------------------------ yo
  ORDS.DEFINE_TEMPLATE(p_module_name => 'plazas', p_pattern => 'yo');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'plazas', p_pattern => 'yo', p_method => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'[
DECLARE
  v_email VARCHAR2(200);
BEGIN
  v_email := int_auth.validar(:token);
  IF v_email IS NULL THEN
    :status_code := 401;
    HTP.p('{"error":"sesion no valida"}');
  ELSE
    HTP.p('{"email":"' || v_email || '"}');
  END IF;
END;]'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name => 'plazas', p_pattern => 'yo', p_method => 'GET',
    p_name => 'X-Token', p_bind_variable_name => 'token',
    p_source_type => 'HEADER', p_param_type => 'STRING', p_access_method => 'IN');

  ------------------------------------------------------------------ sedes
  ORDS.DEFINE_TEMPLATE(p_module_name => 'plazas', p_pattern => 'sedes');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'plazas', p_pattern => 'sedes', p_method => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT id, nombre, plazas, orden FROM int_sedes ' ||
                     'WHERE int_auth.validar(:token) IS NOT NULL ORDER BY orden');
  ORDS.DEFINE_PARAMETER(
    p_module_name => 'plazas', p_pattern => 'sedes', p_method => 'GET',
    p_name => 'X-Token', p_bind_variable_name => 'token',
    p_source_type => 'HEADER', p_param_type => 'STRING', p_access_method => 'IN');

  ------------------------------------------------------------------ estudiantes
  ORDS.DEFINE_TEMPLATE(p_module_name => 'plazas', p_pattern => 'estudiantes');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'plazas', p_pattern => 'estudiantes', p_method => 'GET',
    p_source_type => ORDS.source_type_query,
    p_source      => 'SELECT id, apellidos, nombres, codigo, cedula, correo_inst, ' ||
                     'correo_pers, celular, gpa, creditos, examen, pensum, ' ||
                     'discapacidad, embarazada, hijos, estado_civil, bloqueado, sede_id ' ||
                     'FROM int_estudiantes ' ||
                     'WHERE int_auth.validar(:token) IS NOT NULL ORDER BY apellidos');
  ORDS.DEFINE_PARAMETER(
    p_module_name => 'plazas', p_pattern => 'estudiantes', p_method => 'GET',
    p_name => 'X-Token', p_bind_variable_name => 'token',
    p_source_type => 'HEADER', p_param_type => 'STRING', p_access_method => 'IN');

  ------------------------------------------------------------------ asignar
  ORDS.DEFINE_TEMPLATE(p_module_name => 'plazas', p_pattern => 'asignar');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'plazas', p_pattern => 'asignar', p_method => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'[
DECLARE
  v_email VARCHAR2(200);
BEGIN
  v_email := int_auth.validar(:token);
  IF v_email IS NULL THEN
    :status_code := 401;
    HTP.p('{"error":"sesion no valida"}');
    RETURN;
  END IF;
  IF int_finalizado = 1 THEN
    :status_code := 423;
    HTP.p('{"error":"periodo finalizado"}');
    RETURN;
  END IF;
  UPDATE int_estudiantes SET sede_id = :sede_id WHERE id = :id;
  IF SQL%ROWCOUNT = 0 THEN
    ROLLBACK;
    :status_code := 404;
    HTP.p('{"error":"estudiante no existe"}');
  ELSE
    COMMIT;
    HTP.p('{"ok":true}');
  END IF;
EXCEPTION WHEN OTHERS THEN
  ROLLBACK;
  :status_code := 409;   -- el trigger de cupo llega por aqui
  HTP.p('{"error":"' || REPLACE(SUBSTR(SQLERRM, 1, 200), '"', '''') || '"}');
END;]'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name => 'plazas', p_pattern => 'asignar', p_method => 'POST',
    p_name => 'X-Token', p_bind_variable_name => 'token',
    p_source_type => 'HEADER', p_param_type => 'STRING', p_access_method => 'IN');

  ------------------------------------------------------------------ bloquear
  ORDS.DEFINE_TEMPLATE(p_module_name => 'plazas', p_pattern => 'bloquear');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'plazas', p_pattern => 'bloquear', p_method => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'[
DECLARE
  v_email VARCHAR2(200);
BEGIN
  v_email := int_auth.validar(:token);
  IF v_email IS NULL THEN
    :status_code := 401;
    HTP.p('{"error":"sesion no valida"}');
    RETURN;
  END IF;
  IF int_finalizado = 1 THEN
    :status_code := 423;
    HTP.p('{"error":"periodo finalizado"}');
    RETURN;
  END IF;
  UPDATE int_estudiantes SET bloqueado = :bloqueado WHERE id = :id;
  IF SQL%ROWCOUNT = 0 THEN
    ROLLBACK;
    :status_code := 404;
    HTP.p('{"error":"estudiante no existe"}');
  ELSE
    COMMIT;
    HTP.p('{"ok":true}');
  END IF;
END;]'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name => 'plazas', p_pattern => 'bloquear', p_method => 'POST',
    p_name => 'X-Token', p_bind_variable_name => 'token',
    p_source_type => 'HEADER', p_param_type => 'STRING', p_access_method => 'IN');

  ------------------------------------------------------------------ vaciar
  ORDS.DEFINE_TEMPLATE(p_module_name => 'plazas', p_pattern => 'vaciar');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'plazas', p_pattern => 'vaciar', p_method => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'[
DECLARE
  v_email VARCHAR2(200);
  v_n     NUMBER;
BEGIN
  v_email := int_auth.validar(:token);
  IF v_email IS NULL THEN
    :status_code := 401;
    HTP.p('{"error":"sesion no valida"}');
    RETURN;
  END IF;
  IF int_finalizado = 1 THEN
    :status_code := 423;
    HTP.p('{"error":"periodo finalizado"}');
    RETURN;
  END IF;
  UPDATE int_estudiantes SET sede_id = NULL WHERE sede_id IS NOT NULL;
  v_n := SQL%ROWCOUNT;
  COMMIT;
  HTP.p('{"ok":true,"liberadas":' || v_n || '}');
END;]'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name => 'plazas', p_pattern => 'vaciar', p_method => 'POST',
    p_name => 'X-Token', p_bind_variable_name => 'token',
    p_source_type => 'HEADER', p_param_type => 'STRING', p_access_method => 'IN');

  ------------------------------------------------------------------ config (GET)
  ORDS.DEFINE_TEMPLATE(p_module_name => 'plazas', p_pattern => 'config');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'plazas', p_pattern => 'config', p_method => 'GET',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'[
BEGIN
  IF int_auth.validar(:token) IS NULL THEN
    :status_code := 401;
    HTP.p('{"error":"sesion no valida"}');
  ELSE
    HTP.p('{"finalizado":' || int_finalizado || '}');
  END IF;
END;]'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name => 'plazas', p_pattern => 'config', p_method => 'GET',
    p_name => 'X-Token', p_bind_variable_name => 'token',
    p_source_type => 'HEADER', p_param_type => 'STRING', p_access_method => 'IN');

  ------------------------------------------------------------------ finalizar (POST)
  ORDS.DEFINE_TEMPLATE(p_module_name => 'plazas', p_pattern => 'finalizar');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'plazas', p_pattern => 'finalizar', p_method => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'[
DECLARE
  v_val VARCHAR2(10) := CASE WHEN :finalizado = 1 OR :finalizado = '1' THEN '1' ELSE '0' END;
BEGIN
  IF int_auth.validar(:token) IS NULL THEN
    :status_code := 401;
    HTP.p('{"error":"sesion no valida"}');
    RETURN;
  END IF;
  UPDATE int_config SET valor = v_val WHERE clave = 'finalizado';
  IF SQL%ROWCOUNT = 0 THEN
    INSERT INTO int_config (clave, valor) VALUES ('finalizado', v_val);
  END IF;
  COMMIT;
  HTP.p('{"ok":true,"finalizado":' || v_val || '}');
END;]'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name => 'plazas', p_pattern => 'finalizar', p_method => 'POST',
    p_name => 'X-Token', p_bind_variable_name => 'token',
    p_source_type => 'HEADER', p_param_type => 'STRING', p_access_method => 'IN');

  ------------------------------------------------------------------ salir
  ORDS.DEFINE_TEMPLATE(p_module_name => 'plazas', p_pattern => 'salir');
  ORDS.DEFINE_HANDLER(
    p_module_name => 'plazas', p_pattern => 'salir', p_method => 'POST',
    p_source_type => ORDS.source_type_plsql,
    p_source      => q'[
BEGIN
  int_auth.cerrar(:token);
  HTP.p('{"ok":true}');
END;]'
  );
  ORDS.DEFINE_PARAMETER(
    p_module_name => 'plazas', p_pattern => 'salir', p_method => 'POST',
    p_name => 'X-Token', p_bind_variable_name => 'token',
    p_source_type => 'HEADER', p_param_type => 'STRING', p_access_method => 'IN');

  -- CORS: origenes desde los que el navegador podra llamar a estos endpoints.
  ORDS.SET_MODULE_ORIGINS_ALLOWED(
    p_module_name     => 'plazas',
    p_origins_allowed => 'https://raulalcivarm10.github.io,http://localhost:8093,http://localhost:5817');

  COMMIT;
END;
/

-- Comprobacion: debe listar el modulo 'plazas' con sus 7 plantillas.
SELECT m.name AS modulo, t.uri_template
  FROM user_ords_modules m JOIN user_ords_templates t ON t.module_id = m.id
 ORDER BY t.uri_template;
