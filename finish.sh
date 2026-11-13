#!/usr/bin/env bash
# =============================================================================
# finish.sh - schliesst die PLE-Einreichung in einem Lauf ab.
#
# Voraussetzungen (beide sind EINMALIGE Klicks im Browser, nicht automatisierbar):
#   1. HF-Zugang zum gated Dataset google/physical-engineerings-last-exam
#      -> https://huggingface.co/datasets/google/physical-engineerings-last-exam
#   2. Kaggle-Regeln des Wettbewerbs akzeptiert (fuer die spaetere Einreichung)
#      -> https://www.kaggle.com/competitions/physical-engineerings-last-exam/rules
#
# Was dieses Skript macht:
#   a) prueft HF-Zugang und lokalen Modell-Endpunkt
#   b) erzeugt eine Arbeitskopie mit lokalem Modell (von den Regeln ausdruecklich
#      erlaubt: dev mit eigenem Modell erzeugen, danach auf google-cloud umstellen)
#   c) laeuft die 29 Dev-Aufgaben mit eval/run.py -> artifacts/
#   d) kit check muss gruen sein
#   e) kopiert artifacts/ zurueck, stellt submission.yaml auf das gesponserte
#      Modell, committet und pusht, gibt den 40-stelligen SHA aus
#
# Aufruf:  bash finish.sh
# =============================================================================
set -uo pipefail

KIT="${KIT:-/root/ple}"                     # Klon von github.com/google-research/ple (in WSL)
ENTRY="${ENTRY:-/mnt/c/Users/amer7/openamer-ple-harness}"
LOKAL="${LOKAL:-openamer-max-desktop}"      # lokales Modell fuer die Dev-Laeufe
GESPONSTERT="google-cloud/claude-opus-5-5"  # Zielmodell fuer die Einreichung
ARBEIT="/root/entry-dev"

rot()  { printf "\033[31m%s\033[0m\n" "$*"; }
gruen(){ printf "\033[32m%s\033[0m\n" "$*"; }
info() { printf "\033[36m== %s\033[0m\n" "$*"; }

# --- 1. Voraussetzungen ------------------------------------------------------
info "1/6 Voraussetzungen pruefen"

if ! python3 -c "
import os, sys
from huggingface_hub import hf_hub_download
try:
    hf_hub_download('google/physical-engineerings-last-exam', 'eval.yaml', repo_type='dataset')
except Exception as e:
    print('   HF-Zugang fehlt:', type(e).__name__); sys.exit(1)
print('   HF-Zugang: ok')
" 2>/dev/null; then
    rot "   HF-Token hat keinen Zugang zum Dataset."
    rot "   -> Auf der HF-Seite 'Request access' klicken (angemeldet), dann erneut starten."
    rot "   -> Token muss zum Konto mit Zugang gehoeren:  export HF_TOKEN=..."
    exit 1
fi

if ! curl -s -m 5 -o /dev/null "http://127.0.0.1:11434/api/tags"; then
    rot "   Ollama in WSL antwortet nicht. Starten:  ollama serve &"
    exit 1
fi
gruen "   Ollama: ok"

if ! docker info >/dev/null 2>&1; then
    rot "   Docker laeuft nicht.  service docker start"
    exit 1
fi
gruen "   Docker: ok"

[ -d "$KIT/kit" ] || { rot "   Kit fehlt unter $KIT"; exit 1; }
[ -f "$ENTRY/submission.yaml" ] || { rot "   Entry fehlt unter $ENTRY"; exit 1; }

# --- 2. Arbeitskopie mit lokalem Modell -------------------------------------
info "2/6 Arbeitskopie mit lokalem Modell anlegen (dev-Lauf, regelkonform)"
rm -rf "$ARBEIT"
cp -r "$ENTRY" "$ARBEIT"
rm -rf "$ARBEIT/.git" "$ARBEIT/artifacts"

python3 - "$ARBEIT/submission.yaml" "$LOKAL" <<'PY'
import pathlib, re, sys
p, modell = pathlib.Path(sys.argv[1]), sys.argv[2]
s = p.read_text(encoding="utf-8")
s = re.sub(r"^model_api:.*$", f"model_api: openai-compatible/{modell}", s, count=1, flags=re.M)
if "model_base_url:" not in s:
    s = s.replace("model_api:", "model_base_url: https://llm.example.org/v1\nmodel_api:", 1)
# CA im Entry: der Modell-Test laeuft im Container, Host-Zertifikate helfen nicht
if "env:" not in s:
    s += ("\nenv:\n"
          '  SSL_CERT_FILE: "/opt/harness/src/openamer-ca.pem"\n'
          '  REQUESTS_CA_BUNDLE: "/opt/harness/src/openamer-ca.pem"\n'
          '  NODE_TLS_REJECT_UNAUTHORIZED: "0"\n')
p.write_text(s, encoding="utf-8")
print("   submission.yaml auf lokales Modell umgestellt")
PY

# frisches Repo mit EINEM Commit: sonst laeuft der git clone des Kits in den Timeout
( cd "$ARBEIT" && git init -q && git add -A \
  && git -c user.name="Amer Sacirovic" -c user.email="amer@openamer-max.io" commit -q -m "dev run" )

# --- 3. Dev-Set laufen lassen ----------------------------------------------
info "3/6 29 Dev-Aufgaben laufen lassen (kann Stunden dauern)"
info "     Fortschritt: $KIT/artifacts und /root/.cache/plebench"
export MODEL_API_KEY="${MODEL_API_KEY:-ollama}"
cd "$KIT" || exit 1
if ! uv run python eval/run.py "$ARBEIT" --model-base-url "https://172.17.0.1:8443/v1"; then
    rot "   eval/run.py fehlgeschlagen - Logs unter /root/.cache/plebench"
    exit 1
fi

# --- 4. kit check ----------------------------------------------------------
info "4/6 kit check"
uv run python -m kit check "$ARBEIT" --model-base-url "https://172.17.0.1:8443/v1" || {
    rot "   kit check nicht gruen - nicht committen"; exit 1; }

# --- 5. Artefakte zurueck, submission.yaml auf gesponsertes Modell ---------
info "5/6 Artefakte zurueckkopieren und Modell umstellen"
if [ -d "$ARBEIT/artifacts" ]; then
    rm -rf "$ENTRY/artifacts"
    cp -r "$ARBEIT/artifacts" "$ENTRY/artifacts"
    du -sh "$ENTRY/artifacts" | awk '{print "   artifacts: "$1}'
else
    rot "   keine artifacts/ erzeugt - Abbruch"; exit 1
fi

python3 - "$ENTRY/submission.yaml" "$GESPONSTERT" <<'PY'
import pathlib, re, sys
p, modell = pathlib.Path(sys.argv[1]), sys.argv[2]
s = re.sub(r"^model_api:.*$", f"model_api: {modell}", p.read_text(encoding="utf-8"),
           count=1, flags=re.M)
s = re.sub(r"^model_base_url:.*\n", "", s, flags=re.M)
s = re.sub(r"env:\n(?:  .*\n)+", "", s)
p.write_text(s, encoding="utf-8")
print("   submission.yaml auf " + modell + " umgestellt")
PY

# --- 6. Committen und pushen ----------------------------------------------
info "6/6 committen und pushen"
cd "$ENTRY" || exit 1
git add -A
git -c user.name="Amer Sacirovic" -c user.email="amer@openamer-max.io" \
    commit -q -m "feat: dev artifacts from the 29 public dev tasks

Generated locally with a self-hosted ${LOKAL} model (allowed by the rules);
submission.yaml is set to ${GESPONSTERT} for Stage 2." || echo "   (nichts zu committen)"
git push -q origin HEAD:main || { rot "   push fehlgeschlagen"; exit 1; }

SHA=$(git rev-parse HEAD)
echo
gruen "================================================================"
gruen " FERTIG - Commit fuer die Einreichung:"
gruen "   $SHA"
gruen "   https://github.com/openamer-max/ple-openamer-harness"
gruen "================================================================"
echo
echo "Naechster Schritt (manuell): auf Kaggle den Writeup einreichen,"
echo "diesen SHA eintragen, Cover + 3 Abbildungen in die Media Gallery."
