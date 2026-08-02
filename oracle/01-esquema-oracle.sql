-- ============================================================
--  Tablero de plazas de internado — esquema Oracle
--  Ejecutar en SQL Developer conectado como QUADRA.
--  Abrir este archivo y pulsar "Run Script" (F5), NO "Run Statement".
--  Nombres con prefijo INT_ para no colisionar con otras tablas.
-- ============================================================

CREATE TABLE int_sedes (
  id      VARCHAR2(20)  CONSTRAINT pk_int_sedes PRIMARY KEY,
  nombre  VARCHAR2(200) NOT NULL,
  plazas  NUMBER(5)     NOT NULL CONSTRAINT chk_int_plazas CHECK (plazas >= 0),
  orden   NUMBER(5)     DEFAULT 0 NOT NULL
);

CREATE TABLE int_estudiantes (
  id           NUMBER(10)    CONSTRAINT pk_int_estud PRIMARY KEY,
  apellidos    VARCHAR2(200) NOT NULL,
  nombres      VARCHAR2(200) NOT NULL,
  codigo       VARCHAR2(50),
  cedula       VARCHAR2(30),
  correo_inst  VARCHAR2(200),
  correo_pers  VARCHAR2(200),
  celular      VARCHAR2(30),
  gpa          NUMBER(6,2),
  creditos     NUMBER(8,2),
  examen       NUMBER(6,2),
  pensum       VARCHAR2(50),
  discapacidad VARCHAR2(20),
  embarazada   VARCHAR2(20),
  hijos        NUMBER(4),
  estado_civil VARCHAR2(50),
  bloqueado    NUMBER(1) DEFAULT 0 NOT NULL,   -- 1 = bloqueado manualmente
  sede_id      VARCHAR2(20),
  actualizado  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  CONSTRAINT fk_int_estud_sede FOREIGN KEY (sede_id) REFERENCES int_sedes(id) ON DELETE SET NULL
);

INSERT INTO int_sedes (id, nombre, plazas, orden) VALUES ('heom', 'Hospital Enrique Ortega Moreira', 30, 1);
INSERT INTO int_sedes (id, nombre, plazas, orden) VALUES ('hng',  'Hospital Naval Guayaquil',        19, 2);
INSERT INTO int_sedes (id, nombre, plazas, orden) VALUES ('hagp', 'Hospital Abel Gilbert Ponton',    15, 3);
COMMIT;

-- Regla de cupo. Trigger COMPUESTO a proposito: uno normal daria el error de
-- "tabla mutante" al contar sobre la misma tabla que se esta modificando.
CREATE OR REPLACE TRIGGER trg_int_cupo
FOR INSERT OR UPDATE OF sede_id ON int_estudiantes
COMPOUND TRIGGER
  TYPE t_lista IS TABLE OF NUMBER INDEX BY VARCHAR2(20);
  v_tocadas t_lista;

  BEFORE EACH ROW IS
  BEGIN
    :NEW.actualizado := SYSTIMESTAMP;
    IF :NEW.sede_id IS NOT NULL
       AND (INSERTING OR :OLD.sede_id IS NULL OR :OLD.sede_id <> :NEW.sede_id) THEN
      v_tocadas(:NEW.sede_id) := 1;
    END IF;
  END BEFORE EACH ROW;

  AFTER STATEMENT IS
    v_key  VARCHAR2(20) := v_tocadas.FIRST;
    v_ocup NUMBER;
    v_lim  NUMBER;
  BEGIN
    WHILE v_key IS NOT NULL LOOP
      SELECT plazas  INTO v_lim  FROM int_sedes       WHERE id = v_key;
      SELECT COUNT(*) INTO v_ocup FROM int_estudiantes WHERE sede_id = v_key;
      IF v_ocup > v_lim THEN
        RAISE_APPLICATION_ERROR(-20001,
          'La sede ' || v_key || ' ya no tiene plazas libres (' || v_ocup || '/' || v_lim || ')');
      END IF;
      v_key := v_tocadas.NEXT(v_key);
    END LOOP;
  END AFTER STATEMENT;
END trg_int_cupo;
/

-- Comprobacion: debe mostrar las 3 sedes.
SELECT * FROM int_sedes;
