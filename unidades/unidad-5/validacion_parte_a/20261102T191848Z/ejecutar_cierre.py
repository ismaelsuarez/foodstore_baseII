#!/usr/bin/env python3
"""Arnés de captura de una sola corrida autorizada; no modifica SQL del producto.
Todas las salidas host se crean en exclusiva junto a este archivo. Secretos solo
se generan en memoria y se pasan por nombres de entorno, nunca por argumentos.
No invocar sobre un contenedor existente; no reintenta scripts SQL fallidos.
"""
import datetime
import hashlib
import json
import os
import queue
import subprocess
import threading
import time
from pathlib import Path

RUN = Path(__file__).resolve().parent
OUT = RUN
ROOT = Path.cwd().resolve()
NAME = 'foodstore_u5_m04'
DB = 'foodstore_tpi_oficial'
IMAGE = 'sha256:2d2b8998d31037bf721cfdf764d76ba74171b4fab3431b7f72c27c56ddbdf9e3'
U5 = 'unidades/unidad-5/sql/'
P = U5 + 'pruebas/'
records = []
paths = []
manifest = []
created = False
control = None
secrets = []
base_env = os.environ.copy()
base_env['PYTHONDONTWRITEBYTECODE'] = '1'


def stamp():
    return datetime.datetime.now(datetime.UTC).isoformat()


def save(name, content):
    with (OUT / name).open('x', encoding='utf-8') as f:
        f.write(content)
    os.chmod(OUT / name, 0o600)


def invoke(label, args, *, data=None, env=None, expected=(0,), capture=True):
    start = stamp()
    result = subprocess.run(args, input=data, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, env=env or base_env)
    text = result.stdout
    # A sensitive match never gets published as raw evidence.
    if any(s and s in text for s in secrets):
        save(label + '.txt', 'BLOCKED: salida retenida; contiene un valor sintético exacto.\n')
        raise RuntimeError('Salida sensible retenida: ' + label)
    if capture:
        save(label + '.txt', text)
    records.append({'scope': str(OUT.relative_to(RUN)), 'step': label, 'command': args, 'start': start, 'end': stamp(),
                    'exit_code': result.returncode, 'expected_exit_codes': list(expected)})
    print(label + ': exit=' + str(result.returncode), flush=True)
    return result


def require(label, args, **kwargs):
    r = invoke(label, args, **kwargs)
    if r.returncode:
        raise RuntimeError(label + ': exit=' + str(r.returncode))
    return r.stdout


def psql(user='postgres'):
    return ['docker', 'exec', '-i', NAME, 'psql', '-X', '-w', '-v', 'ON_ERROR_STOP=1',
            '-v', 'u5_base_objetivo=' + DB, '-U', user, '-d', DB]


class Session:
    def __init__(self, appname='u5_control'):
        base_env['PGAPPNAME'] = appname
        self.q = queue.Queue()
        env_args = ['docker', 'exec', '-i', '-e', 'U5_SYN_PWD', '-e', 'U5_SYN_NUEVA', '-e', 'PGAPPNAME', NAME,
                    'psql', '-X', '-w', '-v', 'ON_ERROR_STOP=1', '-v',
                    'u5_base_objetivo=' + DB, '-U', 'postgres', '-d', DB]
        self.proc = subprocess.Popen(env_args, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, text=True, bufsize=1, env=base_env)
        assert self.proc.stdout is not None
        assert self.proc.stdin is not None
        self.output = self.proc.stdout
        self.input = self.proc.stdin
        self.args = env_args
        self.alive = True
        def pump():
            for line in self.output:
                self.q.put(line)
            self.q.put(None)
        threading.Thread(target=pump, daemon=True).start()

    def step(self, label, sql):
        marker = 'RUNNER_COMPLETED_' + label
        start = stamp()
        self.input.write(sql + '\n\\echo ' + marker + '\n')
        self.input.flush()
        lines = []
        complete = False
        while True:
            line = self.q.get(timeout=300)
            if line is None:
                self.alive = False
                break
            if line.rstrip('\n') == marker:
                complete = True
                break
            lines.append(line)
        text = ''.join(lines)
        if any(s and s in text for s in secrets):
            save(label + '.txt', 'BLOCKED: salida retenida por valor sintético exacto.\n')
            raise RuntimeError('Salida sensible: ' + label)
        save(label + '.txt', text)
        rc = 0 if complete else self.proc.wait(timeout=30)
        records.append({'scope': str(OUT.relative_to(RUN)), 'step': label, 'command': self.args, 'sql_input': sql,
                        'start': start, 'end': stamp(), 'exit_code': rc,
                        'exit_semantics': '0 = archivo completado bajo ON_ERROR_STOP; proceso compartido, salida real en control_session_exit',
                        'completed': complete})
        print(label + ': ' + ('completado' if complete else 'ABORTO exit=' + str(rc)), flush=True)
        return complete

    def file(self, label, path):
        return self.step(label, '\\i /repo/' + path)

    def close(self, label='control_session_exit'):
        if self.alive:
            self.input.write('\\q\n')
            self.input.flush()
        self.input.close()
        rc = self.proc.wait(timeout=30)
        self.alive = False
        save(label + '.txt', 'psql_exit_code=' + str(rc) + '\n')
        return rc


def scan_evidence():
    matches = []
    for p in sorted(RUN.rglob('*')):
        if p.is_file():
            # grep return 1 is expected (no matches); never print matching text.
            r = subprocess.run(['grep', '-F', '-q'] + sum((['-e', s] for s in secrets), [])
                               + ['--', str(p)], capture_output=True)
            if r.returncode != 1:
                matches.append((p.name, r.returncode))
    return matches



def run_m05():
    require('02_schema', psql() + ['-1', '-f', '/repo/schema.sql'])
    require('03_seed', psql() + ['-f', '/repo/datos_iniciales.sql'])
    require('04_objetos', psql() + ['-1', '-f', '/repo/tpi/sql/objetos_programables.sql'])
    require('05_tpi_baseline', psql() + ['-f', '/repo/tpi/pruebas/pruebas_objetos_programables.sql'])
    require('06_having_baseline', psql() + ['-f', '/repo/tpi/sql/consultas_cobertura_tpi.sql'])
    require('07_u3_views', psql() + ['-f', '/repo/unidades/unidad-3/sql/views.sql'])
    require('08_u3_materializada', psql() + ['-f', '/repo/unidades/unidad-3/sql/materializadas.sql'])
    require('09_pgcrypto', psql() + ['-c', 'CREATE EXTENSION pgcrypto WITH SCHEMA public;'])
    control = Session()
    steps = [('10_precondiciones', U5+'00_precondiciones.sql'), ('11_f0', P+'01_f0.sql'),
             ('12_roles', U5+'roles.sql'), ('13_funciones', U5+'funciones_seguridad.sql'),
             ('14_f1', P+'02_f1.sql'), ('15_catalogo', P+'10_catalogo.sql'),
             ('16_matriz', P+'11_matriz.sql'), ('17_matriz_efectiva', P+'16_matriz_efectiva.sql'),
             ('18_reservar_ids', P+'12_reservar_ids.sql'), ('19_permisos', P+'20_permisos.sql'),
             ('20_equivalencia', P+'30_equivalencia.sql'), ('21_credenciales', P+'40_credenciales.sql')]
    ok = True
    completed = []
    for label, path in steps:
        if not control.file(label, path):
            ok = False
            save('aborto_control.txt', 'Sesión cerrada por ON_ERROR_STOP en ' + path + '.\n'
                 'No se repite ni se reconstruye F0. Dependientes pendientes BLOCKED (arnés/producto: analizar salida).\n')
            break
        completed.append(label)
    if ok:
        ok = control.file('22_preparar_logins', P+'49_preparar_logins.sql')
        if ok:
            invoke('23_login_reportes', psql('tst_u5_reportes') + ['-f', '/repo/'+P+'50_login_reportes.sql'])
            invoke('24_login_soporte', psql('tst_u5_soporte') + ['-f', '/repo/'+P+'51_login_soporte.sql'])
            invoke('25_nologin', psql('rol_app_lectura') + ['-c', 'SELECT current_user;'], expected=(2,))
            control.step('26_nologin_catalogo', "SELECT rolname,rolcanlogin FROM pg_roles WHERE rolname='rol_app_lectura';")
            ok = control.file('27_limpiar_logins', P+'52_limpiar_logins.sql')
        if ok:
            ok = control.file('28_cierre', P+'99_cierre.sql')
        if ok:
            control.step('29_huella_final', 'SELECT * FROM pg_temp.u5_huella ORDER BY clase,clave;')
            control.step('29_analitica', "SELECT pg_get_viewdef('public.mv_facturacion_categoria_mes'::regclass); SELECT * FROM public.mv_facturacion_categoria_mes ORDER BY categoria_id,mes; SELECT c.nombre,count(DISTINCT p.usuario_id) AS usuarios_del_grupo FROM public.categoria c JOIN public.producto pr ON pr.categoria_id=c.id JOIN public.detalle_pedido d ON d.producto_id=pr.id JOIN public.pedido p ON p.id=d.pedido_id WHERE NOT d.eliminado AND NOT p.eliminado GROUP BY c.id,c.nombre ORDER BY c.id;")
    control.close()
    # Independent regression remains meaningful after an aborted test transaction.
    if '13_funciones' in completed:
        invoke('30_tpi_after', psql() + ['-f', '/repo/tpi/pruebas/pruebas_objetos_programables.sql'])
        invoke('31_having_after', psql() + ['-f', '/repo/tpi/sql/consultas_cobertura_tpi.sql'])
    require('32_final_inventory', psql() + ['-c', "SELECT rolname,rolcanlogin,rolsuper FROM pg_roles WHERE rolname LIKE 'tst\\_u5\\_%' OR rolname IN ('app_web','admin_datos'); SELECT pg_get_userbyid(roleid),pg_get_userbyid(member),admin_option,inherit_option,set_option FROM pg_auth_members ORDER BY 1,2; SELECT 'categoria' AS tabla,count(*) FROM public.categoria UNION ALL SELECT 'usuario',count(*) FROM public.usuario UNION ALL SELECT 'producto',count(*) FROM public.producto UNION ALL SELECT 'pedido',count(*) FROM public.pedido UNION ALL SELECT 'detalle_pedido',count(*) FROM public.detalle_pedido;"])

# Código del nuevo arnés de cierre; se combina con auxiliares de captura ya observados.
import base64
import collections
import hmac
import re
import sys

PREVIOUS = ['20261102T185421Z', '20261102T190345Z']
OLD = RUN.parent / PREVIOUS[1]
NAMES = ['foodstore_u5_m04', 'foodstore_u5_m05']
active = False
stage_status = {}
secret_keys = []


def new_secret(key, prefix=''):
    # Generación externa en shell/OpenSSL; nunca se imprime ni persiste el valor.
    value = subprocess.check_output(['bash', '-c', 'set +x; openssl rand -hex 16'], text=True).strip()
    base_env[key] = prefix + value
    secrets.append(base_env[key])
    secret_keys.append(key)
    return base_env[key]


def manifest_dir(path):
    return ''.join(hashlib.sha256(p.read_bytes()).hexdigest() + '  ' + str(p.relative_to(path)) + '\n'
                   for p in sorted(path.rglob('*')) if p.is_file())


def create_lab(name):
    global NAME, active
    NAME = name
    names = require('00_names_before_create', ['docker', 'ps', '-a', '--format', '{{.Names}}']).splitlines()
    if NAME in names:
        raise RuntimeError('BLOCKED: colisión de nombre, no se toca el recurso existente')
    new_secret('POSTGRES_PASSWORD')
    cmd = ['docker', 'run', '--pull=never', '-d', '--name', NAME, '--network', 'none',
           '-v', str(ROOT) + ':/repo:ro', '-e', 'POSTGRES_PASSWORD', '-e', 'POSTGRES_DB=' + DB,
           '-e', 'POSTGRES_INITDB_ARGS=--auth-host=scram-sha-256 --auth-local=trust', 'postgres:17']
    for setting in ['logging_collector=on', 'log_directory=log', 'log_filename=u5-server.log',
                    'log_rotation_age=0', 'log_rotation_size=0', 'log_statement=mod',
                    'log_parameter_max_length=0', 'log_parameter_max_length_on_error=0',
                    'log_file_mode=0600', 'password_encryption=scram-sha-256',
                    'log_connections=on', 'log_disconnections=on', 'log_error_verbosity=verbose',
                    'log_line_prefix=%m [%p] %a %u@%d ']:
        cmd += ['-c', setting]
    require('01_container_create', cmd)
    active = True
    require('01_isolation', ['docker', 'inspect', NAME, '--format',
            'id={{.Id}} image={{.Image}} network={{.HostConfig.NetworkMode}} bindings={{json .HostConfig.PortBindings}} mounts={{json .Mounts}}'])
    for probe in range(90):
        running = require(f'01_probe_{probe:02d}_running', ['docker', 'inspect', '-f', '{{.State.Running}}', NAME]).strip()
        if running != 'true':
            raise RuntimeError('BLOCKED: contenedor detenido')
        logs = require(f'01_probe_{probe:02d}_init', ['docker', 'logs', NAME])
        if 'PostgreSQL init process complete' in logs:
            r = invoke(f'01_probe_{probe:02d}_ready', ['docker', 'exec', NAME, 'pg_isready', '-U', 'postgres', '-d', DB], expected=(0, 1, 2))
            if r.returncode == 0:
                break
        time.sleep(1)
    else:
        raise RuntimeError('BLOCKED: arranque no confirmado; conservar sondeos')
    require('01_version', psql() + ['-c', "SELECT version(),current_setting('server_version');"])
    require('01_settings', psql() + ['-c', "SELECT name,setting,source FROM pg_settings WHERE name IN ('server_version','log_statement','log_parameter_max_length','log_parameter_max_length_on_error','log_file_mode','password_encryption','logging_collector','log_error_verbosity'); SELECT datname FROM pg_database ORDER BY datname;"])


def sql(label, query, *, tuples=False):
    return require(label, psql() + (['-At'] if tuples else []) + ['-c', query])


def snapshot(label):
    query = """SELECT jsonb_build_object(
 'rutinas',(SELECT jsonb_agg(jsonb_build_array(p.oid::regprocedure::text,pg_get_userbyid(p.proowner),p.prosecdef,p.proconfig,p.proacl::text,md5(pg_get_functiondef(p.oid))) ORDER BY p.oid::regprocedure::text) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN ('calcular_total_pedido','registrar_detalle_pedido','fn_set_subtotal','fn_validar_detalle_vigente','fn_recalcular_total_insert','fn_recalcular_total_update','fn_recalcular_total_delete','api_registrar_detalle_pedido','fn_autenticar','fn_resetear_password')),
 'relaciones',(SELECT jsonb_agg(jsonb_build_array(n.nspname,c.relname,c.relkind::text,pg_get_userbyid(c.relowner),c.relacl::text) ORDER BY n.nspname,c.relname) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','reportes')),
 'columnas',(SELECT jsonb_agg(jsonb_build_array(c.relname,a.attname,a.attacl::text) ORDER BY c.relname,a.attnum) FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relname IN ('categoria','usuario','producto','pedido','detalle_pedido') AND a.attnum>0 AND NOT a.attisdropped),
 'esquemas',(SELECT jsonb_agg(jsonb_build_array(n.nspname,pg_get_userbyid(n.nspowner),n.nspacl::text) ORDER BY n.nspname) FROM pg_namespace n WHERE n.nspname IN ('public','reportes')),
 'membresias',(SELECT jsonb_agg(jsonb_build_array(pg_get_userbyid(roleid),pg_get_userbyid(member),admin_option,inherit_option,set_option) ORDER BY roleid,member) FROM pg_auth_members),
 'adp',(SELECT jsonb_agg(jsonb_build_array(pg_get_userbyid(defaclrole),defaclnamespace::regnamespace::text,defaclobjtype::text,defaclacl::text) ORDER BY defaclrole,defaclnamespace,defaclobjtype) FROM pg_default_acl));"""
    return json.loads(sql(label, query, tuples=True).strip())


ABSENT = """SELECT to_regprocedure('public.api_registrar_detalle_pedido(bigint,bigint,integer)') AS api,
 to_regprocedure('public.fn_autenticar(text,text)') AS auth,
 to_regprocedure('public.fn_resetear_password(bigint,text)') AS reset;
 SELECT count(*) AS funciones_u5 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN ('api_registrar_detalle_pedido','fn_autenticar','fn_resetear_password');
 SELECT count(*) AS entradas_acl_u5 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a WHERE n.nspname='public' AND p.proname IN ('api_registrar_detalle_pedido','fn_autenticar','fn_resetear_password');
 DO $$BEGIN IF EXISTS(SELECT FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN ('api_registrar_detalle_pedido','fn_autenticar','fn_resetear_password')) THEN RAISE EXCEPTION 'M04: función U5 residual'; END IF; END$$;"""


def observe(app):
    return ABSENT + f"""
 SELECT pid,application_name,state,backend_xid FROM pg_stat_activity WHERE application_name='{app}';
 DO $$BEGIN IF (SELECT state FROM pg_stat_activity WHERE application_name='{app}') IS DISTINCT FROM 'idle in transaction' THEN RAISE EXCEPTION 'M04: no está idle in transaction'; END IF; END$$;
 SELECT pid AS m04_pid FROM pg_stat_activity WHERE application_name='{app}' \gset
 \echo M04_PID=:m04_pid
 """


def m04():
    global OUT
    OUT = RUN/'m04'
    create_lab(NAMES[0])
    for label, path, single in [('02_schema','schema.sql',True), ('03_seed','datos_iniciales.sql',False),
                              ('04_objetos','tpi/sql/objetos_programables.sql',True),
                              ('07_u3_views','unidades/unidad-3/sql/views.sql',False),
                              ('08_u3_materializada','unidades/unidad-3/sql/materializadas.sql',False)]:
        require(label, psql() + (['-1'] if single else []) + ['-f', '/repo/'+path])
    sql('09_pgcrypto', 'CREATE EXTENSION pgcrypto WITH SCHEMA public;')
    require('10_precondiciones', psql()+['-f','/repo/'+U5+'00_precondiciones.sql'])
    require('12_roles', psql()+['-f','/repo/'+U5+'roles.sql'])
    original = (ROOT/U5/'funciones_seguridad.sql').read_bytes()
    lines = original.decode().splitlines(keepends=True)
    withheld = [i for i,line in enumerate(lines) if line.strip() == 'COMMIT;']
    if len(withheld) != 1:
        raise RuntimeError('BLOCKED: COMMIT no único; no se cambia el instalador')
    stream = ''.join(line for i,line in enumerate(lines) if i not in withheld)
    save('stream_original_sin_commit.txt', stream)
    save('stream_identidad.json', json.dumps({'original_sha256':hashlib.sha256(original).hexdigest(),
         'original_lines':len(lines),'withheld_line_1based':withheld[0]+1,'sent_original_lines':len(lines)-1,
         'sent_original_sha256':hashlib.sha256(stream.encode()).hexdigest(),
         'mechanism':'stdin pipe; original lines verbatim except withheld COMMIT; no product file changed'},indent=2)+'\n')
    baseline = snapshot('20_catalogo_antes')
    own_assert = """DO $$BEGIN IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN ('api_registrar_detalle_pedido','fn_autenticar','fn_resetear_password'))<>3 THEN RAISE EXCEPTION 'M04: instalación no llegó a las tres funciones'; END IF; END$$;
 SELECT p.proname,pg_get_userbyid(p.proowner),p.prosecdef,p.proacl FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname IN ('api_registrar_detalle_pedido','fn_autenticar','fn_resetear_password') ORDER BY p.proname;"""
    installer = Session('u5_m04_terminate')
    observer = None
    try:
        if not installer.step('30_instalador_stream', stream):
            raise RuntimeError('BLOCKED: stream del instalador abortó antes de interrupción')
        if not installer.step('31_instalador_propio_catalogo', own_assert):
            raise RuntimeError('BLOCKED: catálogo propio de transacción')
        observer = Session('u5_m04_observer')
        if not observer.step('32_segunda_conexion_pre', observe('u5_m04_terminate')):
            raise RuntimeError('BLOCKED: no se confirmó transacción pendiente')
        text = (OUT/'32_segunda_conexion_pre.txt').read_text()
        pid = int(re.search(r'M04_PID=(\d+)',text).group(1))
        if not observer.step('33_terminar_backend', "SELECT pg_terminate_backend(:m04_pid) AS m04_terminated \gset\n\\if :m04_terminated\n\\echo TERMINATED=true\n\\else\nDO $$BEGIN RAISE EXCEPTION 'No se terminó backend'; END$$;\n\\endif"):
            raise RuntimeError('BLOCKED: comando de terminación')
        # psql espera stdin: SELECT 1 permite observar el FATAL asíncrono. No se envía ROLLBACK.
        if installer.step('34_cliente_interrumpido', 'SELECT 1;'):
            raise RuntimeError('FAIL: la conexión sobrevivió a la terminación')
        termination_rc = installer.close('35_instalador_exit')
        if termination_rc == 0:
            raise RuntimeError('FAIL: terminación sin diagnóstico de cliente')
        sql('36_tercera_conexion_ausencia', ABSENT)
        after = snapshot('37_catalogo_despues_terminacion')
        if after != baseline:
            raise RuntimeError('FAIL: cambios de catálogo después de terminación')
        # Control separado, no reintento: mismo stream, otra sesión, salida normal ROLLBACK.
        control = Session('u5_m04_rollback')
        try:
            if not control.step('40_control_stream',stream) or not control.step('41_control_propio_catalogo',own_assert):
                raise RuntimeError('BLOCKED: stream del control')
            if not observer.step('42_control_segunda_conexion',observe('u5_m04_rollback')):
                raise RuntimeError('BLOCKED: observación del control')
            control_pid = int(re.search(r'M04_PID=(\d+)',(OUT/'42_control_segunda_conexion.txt').read_text()).group(1))
            # Solo para registrar el ROLLBACK: mod no registra control transaccional.
            # Se activa después de todo el DDL y se revierte con la transacción; sin credenciales.
            if not control.step('43_control_rollback', "SET LOCAL log_statement = 'all';\nROLLBACK;"):
                raise RuntimeError('FAIL: ROLLBACK de control abortó')
            if control.close('44_control_exit') != 0:
                raise RuntimeError('FAIL: exit de control')
        finally:
            if control.alive:
                control.close('44_control_exit_incompleto')
        sql('45_control_tercera_conexion_ausencia', ABSENT)
        if snapshot('46_catalogo_despues_rollback') != baseline:
            raise RuntimeError('FAIL: cambios de catálogo después de control')
        save('resultado_transacciones.json',json.dumps({'termination_pid':pid,'termination_client_exit':termination_rc,
             'control_pid':control_pid,'control_client_exit':0,'catalogo_antes_despues_igual':True,
             'funciones_ausentes_ambas_ramas':True,'termination_client_sent_rollback':False},indent=2)+'\n')
        stage_status['M04_catalogo'] = 'PASS'
    finally:
        if installer.alive:
            installer.close('instalador_cierre_incompleto')
        if observer is not None and observer.alive:
            observer.close('observador_exit')


def scram():
    global OUT
    OUT = RUN/'scram'
    require('01_hba_explicit_rules', ['docker','exec','-u','postgres',NAME,'sh','-c',
        '''{ printf '%s\n' 'host all all 127.0.0.1/32 scram-sha-256' 'host all all ::1/128 scram-sha-256'; while IFS= read -r line; do printf '%s\n' "$line"; done < "$PGDATA/pg_hba.conf"; } > "$PGDATA/u5_hba.conf"
cp "$PGDATA/u5_hba.conf" "$PGDATA/pg_hba.conf"'''])
    sql('02_reload_hba', 'SELECT pg_reload_conf();')
    sql('03_reglas_efectivas', "SELECT rule_number,line_number,type,database,user_name,address,netmask,auth_method,error FROM pg_hba_file_rules ORDER BY rule_number; SHOW password_encryption; DO $$BEGIN IF EXISTS(SELECT FROM pg_hba_file_rules WHERE error IS NOT NULL) OR (SELECT count(*) FROM pg_hba_file_rules WHERE rule_number IN (1,2) AND auth_method='scram-sha-256' AND address IN ('127.0.0.1','::1'))<>2 THEN RAISE EXCEPTION 'Reglas SCRAM inválidas'; END IF; END$$;")
    password = new_secret('U5_SCRAM_PASSWORD')
    wrong = new_secret('U5_SCRAM_WRONG')
    salt = os.urandom(16)
    salted = hashlib.pbkdf2_hmac('sha256',password.encode(),salt,4096)
    client_key = hmac.digest(salted,b'Client Key','sha256')
    stored = hashlib.sha256(client_key).digest()
    server = hmac.digest(salted,b'Server Key','sha256')
    enc = lambda value: base64.b64encode(value).decode()
    verifier = 'SCRAM-SHA-256$4096:'+enc(salt)+'$'+enc(stored)+':'+enc(server)
    base_env['U5_SCRAM_VERIFIER'] = verifier
    secret_keys.append('U5_SCRAM_VERIFIER')
    secrets.append(verifier)
    template = """SET log_statement = 'none';
SET log_min_error_statement = 'panic';
SHOW log_statement;
SHOW log_min_error_statement;
CREATE ROLE tst_u5_scram LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
\getenv u5_scram_verifier U5_SCRAM_VERIFIER
ALTER ROLE tst_u5_scram PASSWORD :'u5_scram_verifier';
\unset u5_scram_verifier
SELECT rolname,split_part(rolpassword,'$',1)||'$' AS verifier_prefix FROM pg_authid WHERE rolname='tst_u5_scram';
"""
    # El template público nunca contiene el verificador real; se obtiene solo del entorno.
    save('04_asignacion_template.txt',template)
    args = psql()
    args[3:3] = ['-e','U5_SCRAM_VERIFIER']
    require('04_asignacion_protegida',args,data=template)
    sql('05_privilegios_catalogo', "SELECT rolname,rolcanlogin,rolsuper,rolcreatedb,rolcreaterole,rolreplication,rolbypassrls FROM pg_roles WHERE rolname='tst_u5_scram'; SELECT count(*) AS membresias FROM pg_auth_members WHERE member='tst_u5_scram'::regrole OR roleid='tst_u5_scram'::regrole; SELECT has_database_privilege('tst_u5_scram',current_database(),'CONNECT') AS connect_public,has_database_privilege('tst_u5_scram',current_database(),'TEMP') AS temp_public,has_schema_privilege('tst_u5_scram','public','USAGE') AS usage_public,has_function_privilege('tst_u5_scram','public.crypt(text,text)','EXECUTE') AS crypt_public,has_function_privilege('tst_u5_scram','public.gen_salt(text)','EXECUTE') AS salt_public; SELECT datacl FROM pg_database WHERE datname=current_database(); SELECT nspacl FROM pg_namespace WHERE nspname='public'; SELECT count(*) AS grants_relacion_directos FROM pg_class c CROSS JOIN LATERAL aclexplode(c.relacl) a WHERE a.grantee='tst_u5_scram'::regrole; SELECT count(*) AS grants_base_directos FROM pg_database d CROSS JOIN LATERAL aclexplode(d.datacl) a WHERE a.grantee='tst_u5_scram'::regrole;")
    conn = 'host=127.0.0.1 port=5432 dbname='+DB+' user=tst_u5_scram require_auth=scram-sha-256 sslmode=disable '
    tcp = ['docker','exec','-i','-e','PGPASSWORD',NAME,'psql','-X','-w','-v','ON_ERROR_STOP=1','-v','u5_base_objetivo='+DB]
    base_env['PGPASSWORD'] = password
    require('06_tcp_valida',tcp+['--dbname',conn+'application_name=u5_scram_valid','-c',"SELECT current_user,session_user,current_database(),inet_client_addr(),pg_backend_pid(); SELECT ssl FROM pg_stat_ssl WHERE pid=pg_backend_pid();"])
    base_env['PGPASSWORD'] = wrong
    failed = invoke('07_tcp_incorrecta',tcp+['--dbname',conn+'application_name=u5_scram_wrong','-c','SELECT current_user;'],expected=(2,))
    base_env.pop('PGPASSWORD',None)
    if failed.returncode != 2 or 'password authentication failed' not in failed.stdout:
        raise RuntimeError('FAIL: contraseña incorrecta no produjo rechazo esperado')
    sql('08_drop_role', "DROP ROLE tst_u5_scram; SELECT count(*) AS roles_scram_restantes FROM pg_roles WHERE rolname='tst_u5_scram'; DO $$BEGIN IF EXISTS(SELECT FROM pg_roles WHERE rolname='tst_u5_scram') THEN RAISE EXCEPTION 'Rol SCRAM residual'; END IF; END$$;")
    sql('09_settings_globales_preservados', "SHOW log_statement; SHOW log_min_error_statement; SHOW password_encryption;")
    stage_status['SCRAM_cliente'] = 'PASS'


def sec04():
    global OUT
    OUT = RUN/'sec04'
    # Catálogo completo de relaciones legibles, incluidos catálogos del sistema.
    sql('01_todas_relaciones_legibles', "SELECT n.nspname,c.relname,c.relkind,pg_get_userbyid(c.relowner) AS propietario,has_table_privilege('rol_reportes',c.oid,'SELECT') AS select_efectivo FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind IN ('r','p','v','m','f') AND has_table_privilege('rol_reportes',c.oid,'SELECT') ORDER BY n.nspname,c.relname;")
    sql('02_columnas_y_definiciones', "SELECT n.nspname,c.relname,c.relkind,CASE WHEN c.relkind IN ('v','m') THEN pg_get_viewdef(c.oid) ELSE NULL END AS definicion,(SELECT jsonb_agg(jsonb_build_object('columna',a.attname,'tipo',format_type(a.atttypid,a.atttypmod)) ORDER BY a.attnum) FROM pg_attribute a WHERE a.attrelid=c.oid AND a.attnum>0 AND NOT a.attisdropped) AS columnas FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind IN ('r','p','v','m','f') AND has_table_privilege('rol_reportes',c.oid,'SELECT') ORDER BY n.nspname,c.relname;")
    sql('03_analitica_no_sistema', "SELECT n.nspname,c.relname,c.relkind,pg_get_viewdef(c.oid) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE c.relkind IN ('v','m') AND n.nspname NOT IN ('pg_catalog','information_schema') AND n.nspname NOT LIKE 'pg_toast%' AND has_table_privilege('rol_reportes',c.oid,'SELECT') ORDER BY n.nspname,c.relname;")
    sql('04_grupos_seed', "SELECT c.id AS categoria_id,c.nombre AS categoria_nombre,date_trunc('month',p.fecha)::date AS mes,count(DISTINCT p.id) AS pedidos,count(DISTINCT p.usuario_id) AS usuarios_del_grupo,sum(d.cantidad) AS unidades,sum(d.subtotal) AS facturacion FROM public.categoria c JOIN public.producto pr ON pr.categoria_id=c.id JOIN public.detalle_pedido d ON d.producto_id=pr.id JOIN public.pedido p ON p.id=d.pedido_id WHERE NOT d.eliminado AND NOT p.eliminado GROUP BY c.id,c.nombre,date_trunc('month',p.fecha)::date ORDER BY categoria_id,mes;")
    save('README.md', '''# SEC-04 / M03 — revisión final de reidentificación

**Veredicto: aceptación provisional — pendiente de aceptación formal del equipo.**

Texto humano literal: «La revisión humana acepta provisionalmente el uso académico de datos sintéticos y agregados, pero no autoriza exposición de datos personales reales.»

Se inventariaron TODAS las relaciones legibles efectivamente mediante has_table_privilege(rol_reportes, oid, SELECT), incluidos catálogos y vistas del sistema, y sus columnas/definiciones sin leer sus datos. 01/02 conservan ese inventario, no solo los GRANT directos. La analítica no-sistema utilizada es public.mv_facturacion_categoria_mes (03); no se usa una v_resumen_ventas_rol_mes ni se instala otra analítica.

Columnas: categoria_id, categoria_nombre, mes, cantidad_pedidos, unidades_vendidas, facturacion_total. Agrupamiento: c.id, c.nombre, date_trunc('month',pedido.fecha)::date. Se agrega subtotal físico, sin usuarios individuales. Las cohortes del seed por categoría/mes se registran en 04: Pizzas=3 usuarios y Bebidas=2, ambas marzo 2026. No hay cohorte unitaria aquí, pero estos tamaños NO anonimizan ni acreditan ausencia de reidentificación.

Riesgos: conocimiento auxiliar de compras o categorías singulares; cruces con otras fuentes o perfiles; identificación por cantidades/importes raros; diferencias entre snapshots/refresh que revelen una única compra; granularidad mensual combinada con categoría; cambios de dataset que generen cohortes de tamaño uno. USAGE y metadatos públicos no equivalen a acceso a datos privados, pero pueden facilitar comprensión de la estructura. La denegación de usuario/pedido para rol_reportes reduce cruces internos, no elimina fuentes externas ni privilegios de otra identidad.

Condiciones para aceptación formal: revisión explícita del equipo documentada; confirmar dataset exclusivamente sintético y alcance académico; mantener la matriz exacta sin accesos personales; revisar todos los objetos nuevos y cambios de ADP; definir amenaza, mínimo de cohorte/supresión y política contra diferencias temporales si hubiera datos reales; evaluar cruces auxiliares y granularidad; repetir la revisión tras cambios de datos/esquema/refresh; no publicar datos reales ni atribuir garantías de anonimización. La aceptación provisional no autoriza exposición real ni convierte este documento en PASS automático de M03/SEC-04.
''')
    stage_status['SEC04'] = 'aceptación provisional — pendiente de aceptación formal del equipo'


def compare_m05():
    global OUT
    OUT = RUN/'m05'
    raw_results = []
    for file in sorted(OUT.glob('*.txt')):
        if file.name == 'servidor.txt':
            continue
        raw_results += [file.name+':'+line for line in file.read_text().splitlines() if 'RESULT|' in line]
    save('RESULT_resumen.txt','\n'.join(raw_results)+'\n')
    def extract(lines):
        counts = collections.Counter()
        for line in lines:
            found = re.search(r'RESULT\|([^|]+)\|(PASS|FAIL)\|([^|]*)\|(.*)',line)
            if found:
                counts[found.groups()] += 1
        return counts
    current = extract(raw_results)
    previous = extract((OLD/'RESULT_resumen.txt').read_text().splitlines())
    changes = {'solo_anterior':[list(key)+[value] for key,value in (previous-current).items()],
               'solo_actual':[list(key)+[value] for key,value in (current-previous).items()]}
    save('comparacion_RESULT.json',json.dumps(changes,ensure_ascii=False,indent=2)+'\n')
    rows = ['caso\tveredicto\tconteo_anterior\tconteo_actual\tesperado_observado']
    for key in sorted(set(current)|set(previous)):
        rows.append('\t'.join([key[0],key[1],str(previous[key]),str(current[key]),key[2]]))
    save('comparacion_caso_a_caso.tsv','\n'.join(rows)+'\n')
    comparisons = {}
    for name in ['05_tpi_baseline.txt','30_tpi_after.txt','06_having_baseline.txt','31_having_after.txt',
                 '11_f0.txt','14_f1.txt','15_catalogo.txt','16_matriz.txt','17_matriz_efectiva.txt','29_huella_final.txt','32_final_inventory.txt']:
        now = (OUT/name).read_text()
        old = (OLD/name).read_text()
        normalize = lambda text: '\n'.join(line.rstrip() for line in text.splitlines() if not line.startswith('psql:') and line.strip())
        comparisons[name] = {'byte_equal':now==old,'normalized_equal':normalize(now)==normalize(old),
                             'normalization':'trailing spaces, blank lines, NOTICE transport ordering excluded; no semantic fingerprint field discarded'}
        if name in ['05_tpi_baseline.txt','30_tpi_after.txt']:
            comparisons[name]['notice_pass_actual'] = now.count('NOTICE:  PASS:')
            comparisons[name]['notice_pass_anterior'] = old.count('NOTICE:  PASS:')
        if normalize(now) != normalize(old):
            import difflib
            save('diff_'+name,''.join(difflib.unified_diff(normalize(old).splitlines(keepends=True),normalize(now).splitlines(keepends=True),fromfile='anterior',tofile='actual')))
    save('comparacion_fingerprints_y_TPI.json',json.dumps(comparisons,ensure_ascii=False,indent=2)+'\n')
    counts = {'PASS':sum(value for key,value in current.items() if key[1]=='PASS'),
              'FAIL':sum(value for key,value in current.items() if key[1]=='FAIL')}
    save('RESULT_conteos.json',json.dumps(counts,indent=2)+'\n')
    if changes['solo_anterior'] or changes['solo_actual'] or counts != {'PASS':207,'FAIL':0}:
        stage_status['M05'] = 'FAIL/diferencias: revisar evidencia; no corregir ni repetir'
    else:
        stage_status['M05'] = 'PASS: 207 RESULT, mismos casos/veredictos/detalles y multiplicidades'


def capture_destroy():
    global OUT, active
    require('80_log_permissions',['docker','exec',NAME,'stat','-c','%a %U %G %n','/var/lib/postgresql/data/log/u5-server.log'])
    require('81_log_snapshot',['docker','exec','-u','postgres',NAME,'cp','/var/lib/postgresql/data/log/u5-server.log','/var/lib/postgresql/data/log/u5-captured.log'])
    env_args = []
    patterns = []
    for index,value in enumerate(secrets):
        key = f'U5_SCAN_{index}'
        base_env[key] = value
        secret_keys.append(key)
        env_args += ['-e',key]
        patterns.append(f'-e "${key}"')
    grep = 'grep -F -q '+' '.join(patterns)+''' -e '$2a$' -e "PASSWORD '" -- /var/lib/postgresql/data/log/u5-captured.log'''
    result = invoke('82_log_scan_container',['docker','exec',*env_args,NAME,'sh','-c',grep+'\nrc=$?\nprintf "grep_exit_code=%s\\n" "$rc"\nexit "$rc"'],expected=(1,))
    if result.returncode != 1:
        raise RuntimeError('FAIL: log no apto para copia; conservar restringido dentro del contenedor')
    require('83_log_copy',['docker','cp',NAME+':/var/lib/postgresql/data/log/u5-captured.log',str(OUT/'servidor.txt')])
    os.chmod(OUT/'servidor.txt',0o600)
    # Segundo grep sobre copia host; ni contraseñas ni verificadores salen a evidencia.
    check = subprocess.run(['grep','-F','-q']+sum((['-e',value] for value in secrets),[])+['-e','$2a$','-e',"PASSWORD '",'--',str(OUT/'servidor.txt')],capture_output=True)
    save('84_log_scan_host.txt','grep -F exacto passwords/verificador/bcrypt/PASSWORD literal: exit='+str(check.returncode)+'\n')
    if check.returncode != 1:
        raise RuntimeError('FAIL: scan host del log')
    log = (OUT/'servidor.txt').read_text()
    if OUT.name == 'm04' and (OUT/'resultado_transacciones.json').exists():
        observed = json.loads((OUT/'resultado_transacciones.json').read_text())
        pid = observed['termination_pid']
        control_pid = observed['control_pid']
        fatal = [line for line in log.splitlines() if f'[{pid}]' in line and 'terminating connection due to administrator command' in line]
        rollback = [line for line in log.splitlines() if f'[{control_pid}]' in line and 'ROLLBACK' in line]
        save('85_log_interrupcion_vs_rollback.txt','\n'.join(fatal+rollback)+'\n')
        if not fatal or not rollback:
            raise RuntimeError('BLOCKED: falta evidencia de log para interrupción/control')
        stage_status['M04'] = 'PASS: terminación real y ROLLBACK de control distintos; catálogo/ACL/owners intactos'
    if OUT.name == 'm05' and stage_status.get('SCRAM_cliente') == 'PASS':
        lines = [line for line in log.splitlines() if ('u5_scram_valid' in line or 'u5_scram_wrong' in line) and ('authenticated:' in line or 'authentication failed' in line or 'connection authorized:' in line)]
        save('85_scram_log_excerpt.txt','\n'.join(lines)+'\n')
        # La autenticación puede registrarse antes de fijar application_name; corroborar por usuario/método.
        valid = [line for line in log.splitlines() if 'identity="tst_u5_scram"' in line and 'method=scram-sha-256' in line]
        bad = [line for line in log.splitlines() if '28P01' in line and 'password authentication failed for user "tst_u5_scram"' in line]
        save('86_scram_method_and_sqlstate.txt','\n'.join(valid+bad)+'\n')
        if not valid or not bad:
            raise RuntimeError('BLOCKED: método SCRAM o SQLSTATE 28P01 no acreditado en log')
        stage_status['SCRAM'] = 'PASS: require_auth=scram-sha-256, válida y 28P01 incorrecta; cero fugas exactas'
    save('comandos_pre_cleanup.json',json.dumps(records,ensure_ascii=False,indent=2)+'\n')
    matches = scan_evidence()
    save('87_evidence_exact_secret_scan.txt','grep -F de todos los valores exactos contra TODOS los archivos nuevos: '+('PASS, sin coincidencias' if not matches else 'FAIL '+str(matches))+'\n')
    if matches:
        raise RuntimeError('FAIL: evidencia sensible; no confirmar captura')
    volumes = require('88_volumes_created',['docker','inspect',NAME,'--format','{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{println}}{{end}}{{end}}']).splitlines()
    save('89_captura_confirmada.txt','Capturadas todas las salidas disponibles, estados, diagnósticos, catálogos, log y scans. Pasos incompletos se reportan, no se sustituyen. Se autoriza destruir SOLO el contenedor recién creado y su volumen.\n')
    require('90_destroy_only_created',['docker','rm','-f','-v',NAME])
    active = False
    remaining = require('91_names_after_destroy',['docker','ps','-a','--format','{{.Names}}']).splitlines()
    present_volumes = require('92_volumes_after_destroy',['docker','volume','ls','--format','{{.Name}}']).splitlines()
    save('93_cleanup_verification.txt','container_absent='+str(NAME not in remaining)+'\n'+'\n'.join(v+': absent='+str(v not in present_volumes) for v in volumes if v.strip())+'\n')
    if NAME in remaining or any(v in present_volumes for v in volumes if v.strip()):
        raise RuntimeError('FAIL: recurso propio residual')


# MAIN: no reintentos de scripts; cada excepción se conserva y no se corrige producto.
try:
    OUT = RUN
    for folder in ['m04','m05','scram','sec04']:
        (RUN/folder).mkdir(exist_ok=False)
    require('00_git_root',['git','rev-parse','--show-toplevel'])
    branch = require('00_branch',['git','branch','--show-current']).strip()
    require('00_git_status_before',['git','status','--short'])
    before = require('00_docker_ps_before',['docker','ps','-a','--no-trunc'])
    names = require('00_names',['docker','ps','-a','--format','{{.Names}}']).splitlines()
    if branch != 'feat/u5-seguridad' or any(name in names for name in NAMES):
        raise RuntimeError('BLOCKED: rama o colisión de nombres')
    if require('00_image',['docker','image','inspect','postgres:17','--format','{{.Id}}']).strip() != IMAGE:
        raise RuntimeError('BLOCKED: imagen distinta')
    for previous in PREVIOUS:
        save('sha256_'+previous+'_before.txt',manifest_dir(RUN.parent/previous))
    source_paths = [ROOT/'schema.sql',ROOT/'datos_iniciales.sql',ROOT/'tpi/sql/objetos_programables.sql',ROOT/'tpi/pruebas/pruebas_objetos_programables.sql',ROOT/'tpi/sql/consultas_cobertura_tpi.sql',ROOT/'unidades/unidad-3/sql/views.sql',ROOT/'unidades/unidad-3/sql/materializadas.sql']+sorted((ROOT/U5).rglob('*.sql'))
    source_before = ''.join(hashlib.sha256(path.read_bytes()).hexdigest()+'  '+str(path.relative_to(ROOT))+'\n' for path in source_paths)
    save('00_sources_sha256_before.txt',source_before)
    for key,prefix in [('U5_SYN_PWD','u5syn_'),('U5_SYN_NUEVA','u5syn_')]:
        new_secret(key,prefix)
    try:
        m04()
    except Exception as exc:
        save('BLOCKED_o_fallo.txt',type(exc).__name__+': '+str(exc)+'\n')
        stage_status['M04'] = 'BLOCKED/FAIL: revisar diagnóstico, sin repetir'
    finally:
        if active:
            capture_destroy()
    OUT = RUN/'m05'
    create_lab(NAMES[1])
    try:
        run_m05()
        compare_m05()
        sec04()
        scram()
    except Exception as exc:
        save('BLOCKED_o_fallo.txt',type(exc).__name__+': '+str(exc)+'\n')
        stage_status['pendiente'] = 'BLOCKED/FAIL: revisar diagnóstico; no se repite'
    finally:
        OUT = RUN/'m05'
        if active:
            capture_destroy()
except Exception as exc:
    OUT = RUN
    save('BLOCKED_global.txt',type(exc).__name__+': '+str(exc)+'\n')
    stage_status['global'] = 'BLOCKED: revisar evidencia; no afirmar cleanup sin archivos'
finally:
    OUT = RUN
    save('resultados_etapa.json',json.dumps(stage_status,ensure_ascii=False,indent=2)+'\n')
    for previous in PREVIOUS:
        if (RUN/('sha256_'+previous+'_before.txt')).exists():
            after = manifest_dir(RUN.parent/previous)
            save('sha256_'+previous+'_after.txt',after)
            save('preservacion_'+previous+'.txt','byte_identical='+str(after==(RUN/('sha256_'+previous+'_before.txt')).read_text())+'\n')
    if 'source_before' in globals():
        after_sources = ''.join(hashlib.sha256(path.read_bytes()).hexdigest()+'  '+str(path.relative_to(ROOT))+'\n' for path in source_paths)
        save('99_sources_sha256_after.txt',after_sources)
        save('99_sources_preserved.txt','byte_identical='+str(after_sources==source_before)+'\n')
    after_ps = require('99_docker_ps_after',['docker','ps','-a','--no-trunc'])
    if 'before' in globals():
        save('99_existing_containers_preserved.txt','docker_ps_byte_identical='+str(before==after_ps)+'\n')
    require('99_git_status',['git','status','--short'])
    require('99_git_diff_check',['git','diff','--check'])
    save('comandos_finales.json',json.dumps(records,ensure_ascii=False,indent=2)+'\n')
    # Este informe se genera ANTES del último scan exacto, con secretos aún en memoria.
    summary = '# Food Store — Unidad 5 — Cierre experimental de la Parte A\n\nFecha UTC: '+stamp()+'\n\n'
    summary += 'Instancias dedicadas: foodstore_u5_m04 y foodstore_u5_m05; imagen local '+IMAGE+'; PostgreSQL 17.11, red none, sin puertos, repo ro. Versiones/settings/IDs/volúmenes y comandos completos en cada subcarpeta.\n\n'
    summary += '## Resultados observados\n\n'+''.join('- **'+key+'**: '+value+'\n' for key,value in stage_status.items())
    summary += '\n## M04: mecanismo y evidencia\n\nInstalación canónica/dependencias/pgcrypto/precondiciones/roles; stream literal de funciones_seguridad.sql con la única línea COMMIT retenida. SHA-256, línea retenida y conteo exacto en m04/stream_identidad.json; payload público en stream_original_sin_commit.txt. Catálogo propio acredita las tres funciones dentro de la transacción; segunda conexión acredita invisibilidad externa e idle in transaction. pg_terminate_backend desde esa segunda conexión interrumpe realmente al instalador. SELECT 1 posterior solo fuerza al cliente a leer el FATAL: NO se envía ROLLBACK en esa rama. Tercera conexión acredita cero funciones/ACL y catálogo anterior idéntico, incluyendo D3, tablas, columnas, owners, membresías y ADP. Control separado: mismo stream, ROLLBACK explícito, exit 0. Se activa SET LOCAL log_statement=all únicamente DESPUÉS del DDL del control, para registrar su ROLLBACK; vuelve a mod al revertirse. Logs de PID y diagnósticos en m04/85_log_interrupcion_vs_rollback.txt y raw. No se modificó el instalador ni se reemplaza una interrupción por rollback normal.\n'
    summary += '\n## M05: comparación con 20261102T190345Z\n\nMismo orden y scripts: schema -1, seed, objetos -1, TPI baseline/HAVING, vistas U3, materializada con índice propio, pgcrypto, precondiciones → F0 → roles → funciones → F1 → 10 → 11 → 16 → 12 → 20 → 30 → 40 → 49 → 50/51 reales por socket → M06 → 52 → 99 → huella final → TPI/HAVING posterior → inventario. 13/14/15 solo desde sus llamantes. La sesión conserva F0; 0 por paso compartido significa completado bajo ON_ERROR_STOP, exit real en control_session_exit.txt. Comparación por caso/veredicto/detalle/multiplicidad en m05/comparacion_caso_a_caso.tsv y comparacion_RESULT.json; TPI y huellas en comparacion_fingerprints_y_TPI.json. Se normalizan espacios finales/líneas vacías y transporte de NOTICE, no campos semánticos de huella. No se exige igualdad de timestamps, PIDs, OIDs, IDs de contenedor o huecos de secuencia. Esas identidades nuevas de instancia son diferencias de entorno, no defectos de producto. Cualquier diferencia real de catálogo/caso queda explícita en los JSON/diff; no se arregla ni se repite.\n'
    summary += '\n## SCRAM y credenciales\n\nReglas loopback explícitas antepuestas, pg_reload_conf y catálogo sin errores; password_encryption=scram-sha-256. Password aleatoria del shell, verificador calculado en cliente mediante PBKDF2-HMAC-SHA256/4096, salt aleatorio, StoredKey y ServerKey; nunca persistidos. Asignación en sesión superusuario con log_statement=none y log_min_error_statement=panic; el template contiene getenv/interpolación del verificador pero nunca su valor. Se imprime exclusivamente prefijo SCRAM-SHA-256$. La supresión es de ESA sesión, no global, porque mod registraría el DDL sensible. Conexión válida y contraseña incorrecta por TCP 127.0.0.1, require_auth=scram-sha-256 explícito. El servidor usa log_error_verbosity=verbose para acreditar 28P01; extractos en m05/86_scram_method_and_sqlstate.txt. TLS desactivado solo en loopback aislado; SCRAM no implica cifrado de todo el tráfico ni habilitación productiva.\n\nAclaración aprobada por el padre (opción A): tst_u5_scram no recibe GRANT directos ni membresías; conserva los defaults de PUBLIC, incluidos CONNECT, TEMPORARY, USAGE public y EXECUTE pgcrypto. No se modifica PUBLIC ni D9. Privilegios efectivos y ausencia de grants/membresías en scram/05_privilegios_catalogo.txt. DROP y ausencia en scram/08_drop_role.txt. Autenticación PostgreSQL SCRAM es distinta de fn_autenticar/usuario.contrasena bcrypt, cubierta por 40/SEC-18 en M05.\n'
    summary += '\n## SEC-04 / M03\n\n**aceptación provisional — pendiente de aceptación formal del equipo**. Texto literal: «La revisión humana acepta provisionalmente el uso académico de datos sintéticos y agregados, pero no autoriza exposición de datos personales reales.» Inventario efectivo has_table_privilege sobre TODAS las relaciones, columnas/definiciones y cohortes por categoría/mes en sec04/. Riesgos de cohortes pequeñas, cruces y diferencias temporales; condiciones de aceptación en sec04/README.md. No se declara PASS de M03.\n'
    summary += '\n## SEC-01..SEC-20: cambio respecto de la primera instalación\n\n| SEC | Estado/actualización |\n|---|---|\n'
    for number in range(1,21):
        if number == 1:
            verdict = 'PASS si M05=PASS: segunda instalación limpia ejecutada; P/N/R antes pendientes de M05 ahora cubiertos'
        elif number == 4:
            verdict = 'aceptación provisional — pendiente de aceptación formal del equipo; SQL de permisos PASS según M05'
        elif number == 17:
            verdict = 'PASS si M04=PASS y M05=PASS: endurecimiento, suplantación y ahora interrupción real/control observados'
        elif number == 16:
            verdict = 'PASS del intervalo si scans limpios: M05 con bind y SCRAM adicional; sin garantía universal'
        else:
            verdict = 'PASS reiterado si M05=PASS; mismos casos/veredictos que primera instalación, sin cambio de contrato'
        summary += f'| {number:02d} | {verdict} |\n'
    summary += '\nLos condicionales de la tabla deben leerse junto a los estados realmente observados arriba; un paso BLOCKED/FAIL no queda convertido en PASS por la plantilla. Los RESULT originales y sus conteos son la autoridad. TPI esperado y comparado: 29 grupos/37 variantes/30 NOTICE PASS, exit 0, antes y después; P0099 solo en su prueba de atomicidad. P8 esperado y comparado: U5=3, efímeras=0, EXCEPT=0, post-COMMIT=3; 15/52/99 vuelven a acreditar limpieza.\n'
    summary += '\n## Auditoría, fallos y cleanup\n\nLogs de servidor copiados solo tras scan dentro del contenedor y escaneados otra vez en host con grep -F de passwords exactas, verificador exacto, bcrypt y PASSWORD literal. No se entregan coincidencias sensibles. Todos los archivos nuevos, incluido este README, se escanean contra todos los secretos exactos antes de limpiar el entorno. Permisos SO de log 0600. Confirmación de captura antes de cada docker rm -f -v; ausencia de contenedor/volúmenes en 93_cleanup_verification.txt. Inventario Docker previo/posterior y manifiestos SHA-256 de ambos intentos previos y fuentes SQL deben coincidir; archivos de verificación en raíz. Un BLOCKED_o_fallo o BLOCKED_global debe preservarse y prevalece sobre expectativas. No se corrige producto/test ni se oculta un fallo.\n\nTDD OFF por autorización de integración: RED/GREEN no activos. Sin commits, staging, push, merge, cambios en SQL/specs/históricos/odd ni configuración externa. No se acreditan tiempos bcrypt equivalentes, concurrencia de reset, estrés ni anonimización universal. Detenido al concluir; esperar revisión humana.\n'
    save('README.md',summary)
    matches = scan_evidence() if secrets else []
    save('99_final_exact_secret_scan.txt','grep -F passwords/verificador exactos contra todos los archivos, incluidos README/SEC04/arnés: '+('PASS sin coincidencias' if not matches else 'FAIL '+str(matches))+'\n')
    for key in secret_keys+['POSTGRES_PASSWORD','U5_SYN_PWD','U5_SYN_NUEVA','PGPASSWORD','PGAPPNAME']:
        base_env.pop(key,None)
        os.environ.pop(key,None)
    secrets.clear()
    print(json.dumps(stage_status,ensure_ascii=False,indent=2),flush=True)
    if active or 'global' in stage_status or 'pendiente' in stage_status:
        sys.exit(1)
