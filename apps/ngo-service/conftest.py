import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("DATABASE_URL", "postgres://test:test@localhost:5432/test_ngo_db")

# Evita que o import de app.py tente abrir uma conexão real com o Postgres:
# substitui a classe usada por create_pool_with_retry por um stub inerte
# antes do módulo da aplicação ser importado pelos testes.
import psycopg2.pool as _pgpool  # noqa: E402


class _InertPool:
    def __init__(self, *args, **kwargs):
        pass


_pgpool.SimpleConnectionPool = _InertPool
