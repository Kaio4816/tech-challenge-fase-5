import pytest

import app as volunteer_app


class FakeTable:
    def __init__(self, load_error=None, put_item_error=None, scan_items=None):
        self.load_error = load_error
        self.put_item_error = put_item_error
        self.scan_items = scan_items if scan_items is not None else []
        self.put_items = []

    def load(self):
        if self.load_error:
            raise self.load_error

    def put_item(self, Item):
        if self.put_item_error:
            raise self.put_item_error
        self.put_items.append(Item)

    def scan(self, FilterExpression=None):
        return {"Items": self.scan_items}


@pytest.fixture
def client():
    volunteer_app.app.testing = True
    return volunteer_app.app.test_client()


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok", "service": "volunteer-service"}


def test_ready_ok(client, monkeypatch):
    monkeypatch.setattr(volunteer_app, "table", FakeTable())
    resp = client.get("/ready")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ready"


def test_ready_not_ok(client, monkeypatch):
    monkeypatch.setattr(volunteer_app, "table", FakeTable(load_error=Exception("sem conexão")))
    resp = client.get("/ready")
    assert resp.status_code == 503


def test_register_volunteer_missing_fields(client):
    resp = client.post("/volunteers", json={"name": "Só o nome"})
    assert resp.status_code == 400


def test_register_volunteer_success(client, monkeypatch):
    fake_table = FakeTable()
    monkeypatch.setattr(volunteer_app, "table", fake_table)

    resp = client.post("/volunteers", json={"name": "Ana", "email": "ana@a.org", "ngo_id": 1})

    assert resp.status_code == 201
    body = resp.get_json()
    assert body["name"] == "Ana"
    assert body["ngo_id"] == 1
    assert "volunteer_id" in body
    assert fake_table.put_items == [body]


def test_register_volunteer_dynamodb_error(client, monkeypatch):
    monkeypatch.setattr(volunteer_app, "table", FakeTable(put_item_error=Exception("throughput excedido")))

    resp = client.post("/volunteers", json={"name": "Ana", "email": "ana@a.org", "ngo_id": 1})

    assert resp.status_code == 500


def test_get_volunteers_by_ngo(client, monkeypatch):
    items = [{"volunteer_id": "abc", "ngo_id": 1, "name": "Ana"}]
    monkeypatch.setattr(volunteer_app, "table", FakeTable(scan_items=items))

    resp = client.get("/volunteers/1")

    assert resp.status_code == 200
    assert resp.get_json() == items
