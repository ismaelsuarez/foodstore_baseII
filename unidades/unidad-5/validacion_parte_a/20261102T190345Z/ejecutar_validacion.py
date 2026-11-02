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

OUT = Path(__file__).resolve().parent
ROOT = Path.cwd().resolve()
NAME = 'foodstore_u5_validacion_a'
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
    records.append({'step': label, 'command': args, 'start': start, 'end': stamp(),
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
    def __init__(self):
        self.q = queue.Queue()
        env_args = ['docker', 'exec', '-i', '-e', 'U5_SYN_PWD', '-e', 'U5_SYN_NUEVA', NAME,
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
        records.append({'step': label, 'command': self.args, 'sql_input': sql,
                        'start': start, 'end': stamp(), 'exit_code': rc,
                        'exit_semantics': '0 = archivo completado bajo ON_ERROR_STOP; proceso compartido, salida real en control_session_exit',
                        'completed': complete})
        print(label + ': ' + ('completado' if complete else 'ABORTO exit=' + str(rc)), flush=True)
        return complete

    def file(self, label, path):
        return self.step(label, '\\i /repo/' + path)

    def close(self):
        if self.alive:
            self.input.write('\\q\n')
            self.input.flush()
        self.input.close()
        rc = self.proc.wait(timeout=30)
        self.alive = False
        save('control_session_exit.txt', 'psql_exit_code=' + str(rc) + '\n')
        return rc


def scan_evidence():
    matches = []
    for p in sorted(OUT.rglob('*')):
        if p.is_file():
            # grep return 1 is expected (no matches); never print matching text.
            r = subprocess.run(['grep', '-F', '-q'] + sum((['-e', s] for s in secrets), [])
                               + ['--', str(p)], capture_output=True)
            if r.returncode != 1:
                matches.append((p.name, r.returncode))
    return matches


try:
    require('00_root', ['git', 'rev-parse', '--show-toplevel'])
    branch = require('00_branch', ['git', 'branch', '--show-current']).strip()
    require('00_git_status_before', ['git', 'status', '--short'])
    require('00_docker_version', ['docker', '--version'])
    before = require('00_docker_ps_before', ['docker', 'ps', '-a', '--no-trunc'])
    names = require('00_container_names', ['docker', 'ps', '-a', '--format', '{{.Names}}']).splitlines()
    if branch != 'feat/u5-seguridad' or NAME in names:
        raise RuntimeError('BLOCKED: rama inesperada o colisión de nombre')
    image = require('00_image_id', ['docker', 'image', 'inspect', 'postgres:17', '--format', '{{.Id}}']).strip()
    if image != IMAGE:
        raise RuntimeError('BLOCKED: imagen no coincide')
    require('00_openssl_version', ['openssl', 'version'])
    pattern = r"PASSWORD[[:space:]]+'[^']+'|\$2[aby]\$[0-9]{2}\$|-----BEGIN ([A-Z ]+)?PRIVATE KEY-----"
    scanned = subprocess.run(['git', 'grep', '-nE', '-I', pattern, '--',
                              ':!unidades/unidad-5/validacion_parte_a/**'],
                             capture_output=True, text=True)
    # Do not persist possible sensitive values. Location-only report on a match.
    locations = [':'.join(line.split(':', 2)[:2]) + ':[CONTENIDO RETENIDO]'
                 for line in scanned.stdout.splitlines()]
    save('00_secret_scan_tracked.txt', 'command=git grep -nE -I <PASSWORD literal / bcrypt / private key> -- :!unidades/unidad-5/validacion_parte_a/**\n'
         + 'exit_code=' + str(scanned.returncode) + '\n' + '\n'.join(locations) + '\n')
    if scanned.returncode != 1:
        raise RuntimeError('BLOCKED: coincidencia potencial o error en scan rastreado')
    paths = ['schema.sql', 'datos_iniciales.sql', 'tpi/sql/objetos_programables.sql',
             'tpi/pruebas/pruebas_objetos_programables.sql', 'tpi/sql/consultas_cobertura_tpi.sql',
             'unidades/unidad-3/sql/views.sql', 'unidades/unidad-3/sql/materializadas.sql']
    paths += [str(p.relative_to(ROOT)) for p in sorted((ROOT / U5).rglob('*.sql'))]
    manifest = []
    for path in paths:
        f = ROOT / path
        if not f.is_file():
            raise RuntimeError('BLOCKED: falta ' + path)
        manifest.append(hashlib.sha256(f.read_bytes()).hexdigest() + '  ' + path)
    save('00_source_sha256_before.txt', '\n'.join(manifest) + '\n')
    save('00_plan.txt', 'PASS rama/nombre/imagen/herramientas/fuentes/scan.\n'
         'Destino exclusivo: ' + DB + '; u5_base_objetivo explícita en todas las llamadas U5.\n'
         'Autenticación: socket local trust, host SCRAM; conexiones reales por socket en 50/51/M06.\n'
         'Red none; cero puertos; repo solo lectura; sin pull.\n'
         'Servidor: mod, ambos límites de parámetros 0, archivo 0600, SCRAM; collector on; conexiones y desconexiones on.\n'
         'M02: copia restringida dentro del contenedor, grep exacto antes de docker cp; solo copia limpia al repositorio; segundo grep sobre copia host.\n'
         'Credenciales solo en memoria/entorno; sin impresión ni variables -v de contraseña.\n'
         'M04 interrupción y M05 segunda instalación no se improvisan: requieren otra corrida limpia.\n')
    for key, prefix in [('POSTGRES_PASSWORD', ''), ('U5_SYN_PWD', 'u5syn_'), ('U5_SYN_NUEVA', 'u5syn_')]:
        value = subprocess.check_output(['openssl', 'rand', '-hex', '16'], text=True).strip()
        base_env[key] = prefix + value
        secrets.append(base_env[key])
    cmd = ['docker', 'run', '--pull=never', '-d', '--name', NAME, '--network', 'none',
           '-v', str(ROOT) + ':/repo:ro', '-e', 'POSTGRES_PASSWORD', '-e', 'POSTGRES_DB=' + DB,
           '-e', 'POSTGRES_INITDB_ARGS=--auth-host=scram-sha-256 --auth-local=trust', 'postgres:17']
    for setting in ['logging_collector=on', 'log_directory=log', 'log_filename=u5-server.log',
                    'log_rotation_age=0', 'log_rotation_size=0', 'log_statement=mod',
                    'log_parameter_max_length=0', 'log_parameter_max_length_on_error=0',
                    'log_file_mode=0600', 'password_encryption=scram-sha-256',
                    'log_connections=on', 'log_disconnections=on']:
        cmd += ['-c', setting]
    require('01_container_create', cmd)
    created = True
    require('01_container_isolation', ['docker', 'inspect', NAME, '--format',
            'id={{.Id}} image={{.Image}} network={{.HostConfig.NetworkMode}} bindings={{json .HostConfig.PortBindings}} mounts={{json .Mounts}}'])
    for probe in range(90):
        running = require('01_probe_%02d_running' % probe,
                          ['docker', 'inspect', '-f', '{{.State.Running}}', NAME]).strip()
        if running != 'true':
            raise RuntimeError('BLOCKED: contenedor no está running; ver diagnóstico del sondeo')
        logs = require('01_probe_%02d_init_log' % probe, ['docker', 'logs', NAME])
        if 'PostgreSQL init process complete' in logs:
            ready = invoke('01_probe_%02d_pg_isready' % probe,
                           ['docker', 'exec', NAME, 'pg_isready', '-U', 'postgres', '-d', DB],
                           expected=(0, 1, 2))
            if ready.returncode == 0:
                require('01_ready_sql', psql() + ['-c',
                        "SELECT version(), current_setting('server_version');"])
                break
        time.sleep(1)
    else:
        raise RuntimeError('BLOCKED: arranque no confirmado; ver todos los diagnósticos 01_probe')
    save('01_ready.txt', 'running=true; init process complete; pg_isready exit 0; SELECT version/server_version exit 0\n')
    require('01_postgres_version', ['docker', 'exec', NAME, 'postgres', '--version'])
    require('01_psql_version', ['docker', 'exec', NAME, 'psql', '--version'])
    require('01_instance_settings', psql() + ['-c', "SELECT version(); SELECT name,setting,source FROM pg_settings WHERE name IN ('server_version','log_statement','log_parameter_max_length','log_parameter_max_length_on_error','log_file_mode','password_encryption','logging_collector','log_connections','log_disconnections','log_directory','log_filename','log_rotation_age','log_rotation_size'); SELECT datname FROM pg_database ORDER BY datname; SELECT type,database,user_name,address,auth_method,error FROM pg_hba_file_rules;"])
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
except Exception as exc:
    save('BLOCKED_o_fallo_runner.txt', type(exc).__name__ + ': ' + str(exc) + '\n')
    print(type(exc).__name__ + ': ' + str(exc), flush=True)
finally:
    if control is not None and control.alive:
        try:
            control.close()
        except Exception as exc:
            print('Cierre de sesión no acreditado: ' + type(exc).__name__, flush=True)
    if created:
        try:
            require('40_log_permissions', ['docker', 'exec', NAME, 'stat', '-c', '%a %U %G %n', '/var/lib/postgresql/data/log/u5-server.log'])
            require('41_log_snapshot', ['docker', 'exec', '-u', 'postgres', NAME, 'cp',
                                      '/var/lib/postgresql/data/log/u5-server.log', '/var/lib/postgresql/data/log/u5-captured.log'])
            # Scan the restricted copy in the container before any host copy.
            scan = invoke('42_m02_container_scan', ['docker', 'exec', '-e', 'U5_SYN_PWD', '-e', 'U5_SYN_NUEVA', '-e', 'POSTGRES_PASSWORD', NAME, 'sh', '-c',
                '''grep -F -q -e "$U5_SYN_PWD" -e "$U5_SYN_NUEVA" -e "$POSTGRES_PASSWORD" -e '$2a$' -e "PASSWORD '" -- /var/lib/postgresql/data/log/u5-captured.log
rc=$?
printf 'grep_exit_code=%s\\n' "$rc"
if [ "$rc" = 0 ]; then
  grep -nF -e "$U5_SYN_PWD" -e "$U5_SYN_NUEVA" -e "$POSTGRES_PASSWORD" -e '$2a$' -e "PASSWORD '" -- /var/lib/postgresql/data/log/u5-captured.log | cut -d: -f1
fi
exit "$rc"'''], expected=(1,))
            if scan.returncode == 1:
                require('43_docker_cp_log', ['docker', 'cp', NAME+':/var/lib/postgresql/data/log/u5-captured.log', str(OUT/'servidor.txt')])
                os.chmod(OUT/'servidor.txt', 0o600)
                r = subprocess.run(['grep', '-F', '-q'] + sum((['-e',s] for s in secrets), [])
                                   + ['-e', '$2a$', '-e', "PASSWORD '", '--', str(OUT/'servidor.txt')])
                save('44_m02_host_scan.txt', 'grep -F -q valores sintéticos exactos + bcrypt + PASSWORD literal\nexit_code=' + str(r.returncode) + '\n')
                require('45_log_coverage', ['docker', 'exec', NAME, 'sh', '-c',
                        "wc -l /var/lib/postgresql/data/log/u5-captured.log; grep -cF 'statement:' /var/lib/postgresql/data/log/u5-captured.log; grep -cF 'connection authorized:' /var/lib/postgresql/data/log/u5-captured.log; grep -cF 'disconnection:' /var/lib/postgresql/data/log/u5-captured.log"])
            else:
                save('44_m02_FAIL.txt', 'FAIL: log restringido NO incorporado; coincidencia o error en 42. Valores sensibles no publicados; solo números de línea.\n')
            # Raw output and metadata are persisted BEFORE destructive cleanup.
            save('comandos_y_salidas_pre_cleanup.json', json.dumps(records, ensure_ascii=False, indent=2)+'\n')
            all_results = []
            for file in sorted(OUT.glob('*.txt')):
                if file.name == 'servidor.txt':
                    continue
                for line in file.read_text().splitlines():
                    if 'RESULT|' in line:
                        all_results.append(file.name+':'+line)
            save('RESULT_resumen.txt', '\n'.join(all_results)+'\n')
            counts = {'PASS': sum('|PASS|' in line for line in all_results), 'FAIL': sum('|FAIL|' in line for line in all_results)}
            save('RESULT_conteos.json', json.dumps(counts, indent=2)+'\n')
            sensitive = scan_evidence()
            save('46_evidence_secret_scan.txt', 'grep -F -q de los tres valores exactos contra todos los archivos de evidencia\n' + ('PASS: sin coincidencias (exit 1 por archivo)\n' if not sensitive else 'FAIL: '+str(sensitive)+'\n'))
            if sensitive:
                raise RuntimeError('Evidencia sensible: no confirmar captura')
            save('47_confirmacion_captura.txt', 'Evidencias SQL/stdout+stderr, sesión, inventario, RESULT, configuración, permisos y M02 capturadas antes de destruir.\nLos pasos no ejecutados se reportarán BLOCKED, no PASS.\nLog completo del intervalo de pruebas capturado; cierre del servidor posterior fuera de ese intervalo.\n')
            volume_text = require('48_created_volumes', ['docker', 'inspect', NAME, '--format', '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}{{println}}{{end}}{{end}}'])
            require('49_destroy_only_created', ['docker', 'rm', '-f', '-v', NAME])
            names_after = require('50_docker_ps_after', ['docker', 'ps', '-a', '--no-trunc'])
            remaining = require('51_container_names_after', ['docker', 'ps', '-a', '--format', '{{.Names}}'])
            if NAME in remaining.splitlines():
                raise RuntimeError('Contenedor permanece')
            volumes_after = require('52_volumes_after', ['docker', 'volume', 'ls', '--format', '{{.Name}}'])
            save('53_volume_absence.txt', '\n'.join(v+': '+('FAIL presente' if v in volumes_after.splitlines() else 'PASS ausente') for v in volume_text.splitlines() if v.strip())+'\n')
        except Exception as exc:
            save('cleanup_incompleto.txt', type(exc).__name__+': '+str(exc)+'\nNo se afirma destrucción completa sin evidencia.\n')
    save('comandos_y_salidas_final.json', json.dumps(records, ensure_ascii=False, indent=2)+'\n')
    require('90_git_status_after', ['git', 'status', '--short'])
    require('91_git_diff_check', ['git', 'diff', '--check'])
    if manifest:
        now = [hashlib.sha256((ROOT/path).read_bytes()).hexdigest()+'  '+path for path in paths]
        save('92_source_sha256_after.txt', '\n'.join(now)+'\n')
        save('93_source_preservation.txt', 'PASS: todas las fuentes SQL idénticas byte a byte\n' if now == manifest else 'FAIL: fuentes cambiaron\n')
    if secrets:
        matches = scan_evidence()
        save('94_final_secret_scan.txt', 'PASS: sin valores sintéticos exactos en evidencia\n' if not matches else 'FAIL: '+str(matches)+'\n')
    for key in ['POSTGRES_PASSWORD','U5_SYN_PWD','U5_SYN_NUEVA']:
        base_env.pop(key, None)
        os.environ.pop(key, None)
    secrets.clear()
    print('Fin de la única corrida; revisar evidencia en '+str(OUT.relative_to(ROOT)), flush=True)
