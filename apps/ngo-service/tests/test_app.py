import psycopg2
import pytest

import app as ngo_app


class FakeCursor:
    def __init__(self, fetchone_result=None, fetchall_result=None, raise_exc=None):
        self.fetchone_result = fetchone_result
        self.fetchall_result = fetchall_result or []
        self.raise_exc = raise_exc

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False

    def execute(self, query, params=None):
        if self.raise_exc:
            raise self.raise_exc

    def fetchone(self):
        return self.fetchone_result

    def fetchall(self):
        return self.fetchall_result


class FakeConnection:
    def __init__(self, cursor):
        self._cursor = cursor
        self.committed = False
        self.rolled_back = False

    def cursor(self, cursor_factory=None):
        return self._cursor

    def commit(self):
        self.committed = True

    def rollback(self):
        self.rolled_back = True


class FakePool:
    def __init__(self, conn):
        self._conn = conn

    def getconn(self):
        return self._conn

    def putconn(self, conn):
        pass


@pytest.fixture
def client():
    ngo_app.app.testing = True
    return ngo_app.app.test_client()


def use_pool(monkeypatch, cursor):
    monkeypatch.setattr(ngo_app, "pool", FakePool(FakeConnection(cursor)))


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok", "service": "ngo-service"}


def test_ready_ok(client, monkeypatch):
    use_pool(monkeypatch, FakeCursor())
    resp = client.get("/ready")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ready"


def test_ready_not_ok(client, monkeypatch):
    use_pool(monkeypatch, FakeCursor(raise_exc=Exception("sem conexão")))
    resp = client.get("/ready")
    assert resp.status_code == 503


def test_create_ngo_missing_fields(client):
    resp = client.post("/ngos", json={"name": "Só o nome"})
    assert resp.status_code == 400


def test_create_ngo_success(client, monkeypatch):
    created = {"id": 1, "name": "Anjos de Patas", "email": "a@a.org", "cause": "Animal", "city": "Osasco"}
    use_pool(monkeypatch, FakeCursor(fetchone_result=created))

    resp = client.post("/ngos", json={
        "name": "Anjos de Patas", "email": "a@a.org", "cause": "Animal", "city": "Osasco",
    })

    assert resp.status_code == 201
    assert resp.get_json() == created


def test_create_ngo_duplicate_email(client, monkeypatch):
    use_pool(monkeypatch, FakeCursor(raise_exc=psycopg2.IntegrityError("duplicate key")))

    resp = client.post("/ngos", json={
        "name": "X", "email": "dup@a.org", "cause": "Y", "city": "Z",
    })

    assert resp.status_code == 409


def test_get_ngos(client, monkeypatch):
    ngos = [{"id": 2, "name": "B"}, {"id": 1, "name": "A"}]
    use_pool(monkeypatch, FakeCursor(fetchall_result=ngos))

    resp = client.get("/ngos")

    assert resp.status_code == 200
    assert resp.get_json() == ngos


def test_get_ngo_by_id_found(client, monkeypatch):
    ngo = {"id": 1, "name": "Anjos de Patas"}
    use_pool(monkeypatch, FakeCursor(fetchone_result=ngo))

    resp = client.get("/ngos/1")

    assert resp.status_code == 200
    assert resp.get_json() == ngo


def test_get_ngo_by_id_not_found(client, monkeypatch):
    use_pool(monkeypatch, FakeCursor(fetchone_result=None))

    resp = client.get("/ngos/999")

    assert resp.status_code == 404
