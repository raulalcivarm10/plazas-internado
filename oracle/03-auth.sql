-- ============================================================
--  Usuarios y sesiones del tablero — Oracle
--  Ejecutar con Run Script (F5) despues de 01-esquema-oracle.sql.
--
--  Las contrasenas NO se guardan: solo su hash SHA-256 con sal.
--  Este archivo NO contiene ninguna contrasena; los usuarios los
--  creas TU al final llamando a int_auth.crear_usuario (ver abajo).
-- ============================================================

CREATE TABLE int_usuarios (
  email       VARCHAR2(200) CONSTRAINT pk_int_usu PRIMARY KEY,
  sal         RAW(16)       NOT NULL,
  clave_hash  RAW(32)       NOT NULL,
  creado      TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL
);

CREATE TABLE int_sesiones (
  token  VARCHAR2(64)  CONSTRAINT pk_int_ses PRIMARY KEY,
  email  VARCHAR2(200) NOT NULL,
  vence  TIMESTAMP     NOT NULL,
  CONSTRAINT fk_int_ses_usu FOREIGN KEY (email) REFERENCES int_usuarios(email) ON DELETE CASCADE
);

CREATE OR REPLACE PACKAGE int_auth AS
  -- Crea o actualiza un usuario (la contrasena se hashea, nunca se guarda).
  PROCEDURE crear_usuario(p_email VARCHAR2, p_clave VARCHAR2);
  -- Valida credenciales y devuelve un token de sesion (12 horas).
  FUNCTION login(p_email VARCHAR2, p_clave VARCHAR2) RETURN VARCHAR2;
  -- Devuelve el email si el token es valido y vigente; NULL si no.
  FUNCTION validar(p_token VARCHAR2) RETURN VARCHAR2;
  -- Cierra la sesion del token.
  PROCEDURE cerrar(p_token VARCHAR2);
END int_auth;
/

CREATE OR REPLACE PACKAGE BODY int_auth AS

  -- STANDARD_HASH solo existe en SQL (no en expresiones PL/SQL): por eso se
  -- invoca via SELECT ... FROM dual y el resultado se guarda en variable.
  FUNCTION hash_clave(p_sal RAW, p_clave VARCHAR2) RETURN RAW IS
    v_hash RAW(32);
  BEGIN
    SELECT STANDARD_HASH(UTL_RAW.CONCAT(p_sal, UTL_RAW.CAST_TO_RAW(p_clave)), 'SHA256')
      INTO v_hash
      FROM dual;
    RETURN v_hash;
  END hash_clave;

  PROCEDURE crear_usuario(p_email VARCHAR2, p_clave VARCHAR2) IS
    v_sal   RAW(16) := SYS_GUID();
    v_email VARCHAR2(200) := LOWER(TRIM(p_email));
    v_hash  RAW(32);
  BEGIN
    IF v_email IS NULL OR p_clave IS NULL OR LENGTH(p_clave) < 6 THEN
      RAISE_APPLICATION_ERROR(-20400, 'Email vacio o contrasena de menos de 6 caracteres');
    END IF;
    -- El hash se calcula ANTES: una funcion privada del body no puede
    -- llamarse dentro de una sentencia SQL como el MERGE.
    v_hash := hash_clave(v_sal, p_clave);
    MERGE INTO int_usuarios u
    USING (SELECT v_email AS email FROM dual) s
    ON (u.email = s.email)
    WHEN MATCHED THEN UPDATE SET u.sal = v_sal, u.clave_hash = v_hash
    WHEN NOT MATCHED THEN INSERT (email, sal, clave_hash)
      VALUES (s.email, v_sal, v_hash);
    COMMIT;
  END crear_usuario;

  FUNCTION login(p_email VARCHAR2, p_clave VARCHAR2) RETURN VARCHAR2 IS
    v_u     int_usuarios%ROWTYPE;
    v_token VARCHAR2(64);
    v_raw   RAW(32);
  BEGIN
    BEGIN
      SELECT * INTO v_u FROM int_usuarios WHERE email = LOWER(TRIM(p_email));
    EXCEPTION WHEN NO_DATA_FOUND THEN
      -- Mismo mensaje que clave mala: no revelar si el correo existe.
      RAISE_APPLICATION_ERROR(-20401, 'Correo o contrasena incorrectos');
    END;

    IF v_u.clave_hash <> hash_clave(v_u.sal, p_clave) THEN
      RAISE_APPLICATION_ERROR(-20401, 'Correo o contrasena incorrectos');
    END IF;

    -- Limpieza de sesiones vencidas al pasar.
    DELETE FROM int_sesiones WHERE vence < SYSTIMESTAMP;

    -- Token impredecible: incluye material secreto (hash) ademas del GUID.
    SELECT STANDARD_HASH(
             UTL_RAW.CONCAT(
               SYS_GUID(),
               v_u.clave_hash,
               UTL_RAW.CAST_TO_RAW(TO_CHAR(SYSTIMESTAMP, 'YYYYMMDDHH24MISSFF6'))
             ), 'SHA256')
      INTO v_raw
      FROM dual;
    v_token := RAWTOHEX(v_raw);

    INSERT INTO int_sesiones (token, email, vence)
    VALUES (v_token, v_u.email, SYSTIMESTAMP + INTERVAL '12' HOUR);
    COMMIT;
    RETURN v_token;
  END login;

  FUNCTION validar(p_token VARCHAR2) RETURN VARCHAR2 IS
    v_email int_sesiones.email%TYPE;
  BEGIN
    SELECT email INTO v_email
      FROM int_sesiones
     WHERE token = p_token AND vence > SYSTIMESTAMP;
    RETURN v_email;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    RETURN NULL;
  END validar;

  PROCEDURE cerrar(p_token VARCHAR2) IS
  BEGIN
    DELETE FROM int_sesiones WHERE token = p_token;
    COMMIT;
  END cerrar;

END int_auth;
/

-- ============================================================
--  CREAR LOS USUARIOS — esto lo haces TU en SQL Developer,
--  reemplazando LA_CLAVE por la contrasena real (no la pongas
--  en chats ni archivos). Puedes repetirlo para cambiar claves.
-- ============================================================
-- BEGIN
--   int_auth.crear_usuario('rfalcivarm@uees.edu.ec', 'LA_CLAVE');
--   int_auth.crear_usuario('diazmora@uees.edu.ec',  'LA_CLAVE');
-- END;
-- /

-- Prueba (con SET SERVEROUTPUT ON): debe imprimir un token de 64 caracteres.
-- DECLARE t VARCHAR2(64);
-- BEGIN
--   t := int_auth.login('rfalcivarm@uees.edu.ec', 'LA_CLAVE');
--   DBMS_OUTPUT.PUT_LINE('token: ' || t);
-- END;
-- /
