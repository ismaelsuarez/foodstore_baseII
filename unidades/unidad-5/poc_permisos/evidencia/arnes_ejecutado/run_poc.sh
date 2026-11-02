#!/usr/bin/env bash
# POC U5 — ejecución por pasos (design.md §13.3) en un contenedor descartable (D14).
# Uso: ./run_poc.sh <instancia|p0|p1|p2|p3p4|t12|p5|p6|t07|p7|p8|destruir>
# El contenedor no tiene red (--network none): solo se accede con docker exec.
set -euo pipefail

POC_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$POC_DIR/../foodstore_baseII" && pwd)"
OUT="$POC_DIR/salidas"
CONTAINER=foodstore_u5_poc
IMAGE=postgres:17

psql_poc() {
    docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d foodstore_u5_poc "$@"
}

case "${1:-}" in
    instancia)
        if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
            echo "El contenedor $CONTAINER ya existe; no se reutiliza." >&2
            exit 2
        fi
        docker image inspect "$IMAGE" --format 'imagen={{.Id}}' | tee "$OUT/00_instancia.txt"
        docker run -d --name "$CONTAINER" --network none \
            -e POSTGRES_HOST_AUTH_METHOD=trust \
            -e POSTGRES_DB=foodstore_u5_poc \
            -v "$REPO_DIR:/repo:ro" -v "$POC_DIR/sql:/poc:ro" \
            "$IMAGE" >> "$OUT/00_instancia.txt"
        until docker logs "$CONTAINER" 2>&1 | grep -q 'PostgreSQL init process complete'; do
            sleep 1
        done
        until docker exec "$CONTAINER" pg_isready -U postgres -d foodstore_u5_poc >/dev/null; do
            sleep 1
        done
        docker exec "$CONTAINER" psql --version | tee -a "$OUT/00_instancia.txt"
        ;;
    p0)    psql_poc -f /poc/01_p0_inventario.sql > "$OUT/01_p0_inventario.txt" 2>&1 ;;
    p1)
        {
            psql_poc -f /poc/00_guardas.sql
            psql_poc -f /poc/00_guarda_sin_roles.sql
            psql_poc -1 -f /repo/schema.sql
            psql_poc -1 -f /repo/tpi/sql/objetos_programables.sql
            psql_poc -f /poc/02_vp_post_p1.sql
        } > "$OUT/02_p1_instalacion.txt" 2>&1
        ;;
    p2)
        psql_poc -At -f /poc/huella.sql > "$OUT/f0_huella.txt" 2>&1
        psql_poc -f /poc/03_p2_fixtures.sql > "$OUT/03_p2_fixtures.txt" 2>&1
        ;;
    p3p4)  psql_poc -f /poc/04_p3_p4_roles_matriz.sql > "$OUT/04_p3_p4_roles.txt" 2>&1 ;;
    t12)   psql_poc -f /poc/05_t12_atomicidad.sql > "$OUT/05_t12.txt" 2>&1 ;;
    p5)
        psql_poc -f /poc/06_p5_api.sql > "$OUT/06_p5_api.txt" 2>&1
        psql_poc -f /poc/acl_tablas.sql > "$OUT/acl_tablas_f1.txt" 2>&1
        ;;
    p6)    psql_poc -f /poc/07_pruebas.sql > "$OUT/07_pruebas.txt" 2>&1 ;;
    t07)   psql_poc -f /poc/08_t07_ablacion.sql > "$OUT/08_t07.txt" 2>&1 ;;
    p7)
        psql_poc -At -f /poc/huella.sql > "$OUT/f1_huella.txt" 2>&1
        diff "$OUT/f0_huella.txt" "$OUT/f1_huella.txt" > "$OUT/t14_diff.txt" || true
        ;;
    p8)    psql_poc -f /poc/09_p8_limpieza.sql > "$OUT/09_p8_limpieza.txt" 2>&1 ;;
    destruir)
        docker logs "$CONTAINER" > "$OUT/servidor.log" 2>&1
        docker rm -f -v "$CONTAINER"
        if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
            echo "El contenedor $CONTAINER sigue existiendo." >&2
            exit 1
        fi
        echo "Contenedor $CONTAINER y su volumen anónimo eliminados."
        ;;
    *)
        echo "Uso: $0 <instancia|p0|p1|p2|p3p4|t12|p5|p6|t07|p7|p8|destruir>" >&2
        exit 2
        ;;
esac
