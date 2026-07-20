import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
os.environ.setdefault("AWS_DYNAMODB_TABLE", "TestVolunteers")
os.environ.setdefault("AWS_REGION", "us-east-1")

# Evita que o import de app.py tente falar com o DynamoDB de verdade:
# substitui boto3.resource por um dublê inerte antes do módulo da aplicação
# ser importado pelos testes.
import boto3  # noqa: E402


class _InertTable:
    def load(self):
        pass


class _InertResource:
    def Table(self, name):
        return _InertTable()


def _inert_resource(*args, **kwargs):
    return _InertResource()


boto3.resource = _inert_resource
