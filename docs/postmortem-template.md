# Post-Mortem — <título curto do incidente>

> Copie este arquivo para `docs/postmortem-<AAAA-MM-DD>-<slug>.md` e preencha.
> Regras do processo (blameless, prazo de 48h, quando é obrigatório) em
> [`itsm-incident-flow.md`](itsm-incident-flow.md#4-post-mortem).
> **Post-mortem blameless**: descreva o que o sistema permitiu, não quem errou.

## Resumo

| Campo | Valor |
|---|---|
| **Data** | AAAA-MM-DD |
| **Severidade** | `critical` / `warning` |
| **Serviço afetado** | ex.: `donation-service` (Hot Path) |
| **Ambiente** | `primary` (us-east-1) / `dr` (us-east-2) |
| **Início do impacto** | HH:MM:SS UTC |
| **Detecção** | HH:MM:SS UTC |
| **Mitigação aplicada** | HH:MM:SS UTC |
| **Fim do impacto (recuperação)** | HH:MM:SS UTC |
| **MTTD** (detecção − impacto) | MM min |
| **MTTR** (recuperação − impacto) | **MM min** |
| **Autor(es)** | — |

Uma ou duas frases descrevendo o que aconteceu, em linguagem acessível.

## Impacto

- **Usuários/negócio**: ex.: N requisições de doação afetadas; nenhuma doação
  perdida (ou: N doações não registradas).
- **SLI afetado**: disponibilidade e/ou latência de `POST /donations`.
- **Consumo de error budget**: MM min de 43,2 min/30d (**XX%**).
- **SLA externo (99,5%)**: violado? sim/não.
- **Dados**: houve perda? qual? (ver RPO em [`dr-plan.md`](dr-plan.md) se houve
  failover)

## Detecção

- **Como foi detectado**: alerta (`<nome do alerta>`) / anomalia do New Relic /
  relato de usuário.
- **Alerta funcionou como esperado?** Se não: disparou tarde, não disparou, ou
  disparou por outro sintoma que não a causa?
- **Evidência**: print do dashboard, do alerta ou do issue.

## Linha do tempo

| Hora (UTC) | Evento |
|---|---|
| HH:MM:SS | ... |
| HH:MM:SS | ... |

## Causa raiz

Descrição técnica. Se útil, os **5 porquês**:

1. Por que houve impacto? →
2. Por que isso aconteceu? →
3. ... →
4. ... →
5. ... → **causa raiz**

## Resolução

O que efetivamente restaurou o serviço. Deixar explícito se foi **automação**
(self-heal do ArgoCD, probe, HPA, rollback) ou **ação humana** — a proporção
entre as duas coisas é o principal indicador de maturidade operacional aqui.

## O que funcionou bem

- ...

## O que não funcionou / poderia ser melhor

- ...

## Ações corretivas

| # | Ação | Tipo | Dono | Prazo | Status |
|---|---|---|---|---|---|
| 1 | | prevenir / detectar / mitigar | | | aberto |

Tipos: **prevenir** (evita a recorrência), **detectar** (encurta o MTTD),
**mitigar** (encurta o MTTR).

## Comunicação realizada

| Público | Quando | Canal | Link/modelo |
|---|---|---|---|
| Plantão | | e-mail (Workflow New Relic) | |
| Diretoria | | e-mail | modelo de `itsm-incident-flow.md` |
| ONGs parceiras | | e-mail | modelo de `itsm-incident-flow.md` |
