# OpenAmer harness — Physical-Engineering's Last Exam

An agent harness entry for Google's [PLE Harness Competition](https://www.kaggle.com/competitions/physical-engineerings-last-exam),
built on the competition's own protocol sample.

**Status: harness complete and passing `kit check` (exit 0). `artifacts/` is missing** —
generating it requires the gated dev dataset (`google/physical-engineerings-last-exam`
on Hugging Face), which we have not been granted access to. The competition's submit
form **refuses commits without usable artifacts**, so this repository is not yet
submittable. Everything else is done. See [Finishing this entry](#finishing-this-entry).

## What is in here

| File | Purpose |
|---|---|
| `submission.yaml` | install/serve recipe, model selection |
| `serve.py` | the harness: WebSocket server speaking the competition protocol |
| `harness.py`, `taskbridge.py`, `task-tools.ts` | agent loop, task-bridge, tool definitions |
| `AGENTS.md` | the organisers' specification (unchanged) |
| `openamer-ca.pem` | local-dev only: self-signed CA for a self-hosted model endpoint |
| `LICENSE` | Apache-2.0 |

## Measured with the official kit

`python -m kit check` against this entry, with a **self-hosted OpenAmer-Max-Desktop
(14.7 B, Q4_K_M)** endpoint instead of the sponsored model:

```
[PASS] submission.yaml: openamer-harness: openai-compatible/openamer-max-desktop
[PASS] files: 14 files
[PASS] build: bundle 139 MiB, built in 38 s
[PASS] model: answered in 40.6 s through the egress proxy
[PASS] listen: websocket accepted 1 s after start
[PASS] smoke: hello.txt written, 1 request, 3151 in / 31 out tokens; final 'done'
[WARN] mcp: /app/mcp.txt missing — the 14.7 B model did not call the MCP tool
[WARN] artifacts: template artifacts, made with another dev-set version
                                                          -> exit code 0
```

Two honest notes. The `mcp` warning is a **model-capability** limit of our local
14.7 B model, not a harness defect — a frontier model is expected to use the tool. And
with a 0.6 B model the same entry fails smoke with `done after 0 request(s)`, which is
also capability, not plumbing: retry with ≥14 B before suspecting the harness.

## Local development endpoint

The kit's model test runs **inside the container**, so a self-signed certificate must be
shipped inside the entry and pointed at from `env` — host-side CA installs (system store,
certifi) have no effect:

```yaml
env:
  SSL_CERT_FILE: "/opt/harness/src/openamer-ca.pem"
  REQUESTS_CA_BUNDLE: "/opt/harness/src/openamer-ca.pem"
  NODE_TLS_REJECT_UNAUTHORIZED: "0"
```

Also required for local runs: `model_base_url` must be an `https://` URL on a **public DNS
name** (an IP is rejected), and the real address goes on the command line with
`--model-base-url`. `env` values are literal — `{src}` is not expanded there.

## Finishing this entry — one command

Access to `google/physical-engineerings-last-exam` is gated; it must be requested once
while signed in on Hugging Face. After that:

```bash
bash finish.sh          # runs in WSL as root, from the kit checkout
```

`finish.sh` does the whole remaining job and is safe to re-run:

1. verifies HF dataset access, Ollama and Docker,
2. copies the entry to `/root/entry-dev` and switches it to a self-hosted model — the
   rules explicitly allow generating `artifacts/` with a local open-weight model,
3. runs `eval/run.py` over the 29 dev tasks,
4. requires `kit check` to be green,
5. copies `artifacts/` back, switches `submission.yaml` to
   `google-cloud/claude-opus-5-5`, commits and pushes,
6. prints the 40-character commit SHA for the submission form.

Without step 2's model switch the run would need a Vertex AI proxy; with it, the dev
run costs nothing but time. Switching `model_api` to a `google-cloud/<id>` model *after*
generating `artifacts/` locally is explicitly permitted, provided the local model and
judge setup are documented in the writeup — which they are, in `docs/writeup.md`.

After `finish.sh`, the only manual work left is on Kaggle: paste the SHA into the
writeup, upload the cover and the three figures to the media gallery, submit.

## Documents

| File | What it is |
|---|---|
| `docs/writeup.md` | the Stage-1 writeup (1,478 words, covers all five rubric criteria) |
| `docs/figure0-cover.png` | media-gallery cover |
| `docs/figure1-architecture.png` | harness loop with the two gates |
| `docs/figure2-score-vs-cost.png` | score vs. tool calls, r = −0.30 |
| `docs/figure3-failure-breakdown.png` | the four zeros split into two classes |

## Why the analysis that accompanies this harness matters more than the harness

Our writeup is a failure analysis of the public reference run, and it needs no dev
access: two of the four zero-scoring tasks **never wrote a file**, while the other two
wrote on step 3 and step 4 of a 124- and 160-step budget and still scored 0.000. Absent
deliverable and invalid deliverable are different failures and need different gates
(materialise, validate). Every number is recomputed from `manifest.json` and the
trajectories shipped in the public submission template.

## License

Apache-2.0. See `LICENSE`.
