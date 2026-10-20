# dramalive-analysis
#
#   make help          — esto
#   make backend       — API de referencia en :8080
#   make client-web    — cliente web + backend en :5173 (todo junto)
#   make test          — suite de contrato del backend
#   make fetch-web     — descarga el build web público
#   make triage APK=…  — triage de un APK
#   make sanitize      — comprueba que no se filtran secretos
#   make push          — crea/sube el repo en tu GitHub

SHELL      := /bin/bash
ROOT       := $(shell pwd)
BACKEND    := $(ROOT)/backend
CLIENT     := $(ROOT)/client
API_PORT   ?= 8080
WEB_PORT   ?= 5173
BASE       ?= https://web.dramalive.cc
APK        ?= $(ROOT)/artifacts/apk/dramalive.apk
REPO       ?= dramalive-analysis

.DEFAULT_GOAL := help

.PHONY: help
help: ## Muestra esta ayuda
	@printf '\n\033[1mdramalive-analysis\033[0m\n\n'
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}'
	@printf '\n'

# ------------------------------------------------------------------ servidor

.PHONY: backend
backend: ## API de referencia en http://localhost:8080
	@command -v node >/dev/null || { echo "falta node >= 18"; exit 1; }
	@cd $(BACKEND) && PORT=$(API_PORT) HOST=0.0.0.0 node src/index.js

.PHONY: backend-passthrough
backend-passthrough: ## Igual, pero proxifica los 'source' del catálogo propio (contenido libre)
	@cd $(BACKEND) && PASSTHROUGH=1 PORT=$(API_PORT) HOST=0.0.0.0 node src/index.js

.PHONY: client-web
client-web: ## Cliente web + backend en http://localhost:5173 (backend bajo /backend)
	@command -v node >/dev/null || { echo "falta node >= 18"; exit 1; }
	@WEB_PORT=$(WEB_PORT) API_PORT=$(API_PORT) node backend/dev-server.js

# --------------------------------------------------------------------- test

.PHONY: test
test: ## Suite de contrato del backend (85 aserciones)
	@cd $(BACKEND) && bash test.sh

.PHONY: check
check: test ## Alias de test

# ------------------------------------------------------------------ análisis

.PHONY: fetch-web
fetch-web: ## Descarga el build web público de $(BASE)
	@BASE=$(BASE) bash analysis/scripts/fetch_web_artifacts.sh

.PHONY: endpoints-web
endpoints-web: ## Extrae URLs/rutas de main.dart.js
	@test -f artifacts/raw/main.dart.js || $(MAKE) --no-print-directory fetch-web
	@python3 analysis/scripts/extract_endpoints.py artifacts/raw/main.dart.js

.PHONY: triage
triage: ## Triage de un APK:  make triage APK=/ruta/a/app.apk
	@test -f "$(APK)" || { echo "no existe $(APK) — pasa APK=/ruta/al.apk"; exit 1; }
	@bash analysis/scripts/apk_triage.sh "$(APK)"

.PHONY: endpoints-apk
endpoints-apk: ## Extrae URLs/dominios de los DEX del APK
	@test -f "$(APK)" || { echo "no existe $(APK)"; exit 1; }
	@python3 analysis/scripts/extract_endpoints.py --apk "$(APK)"

.PHONY: deps-analysis
deps-analysis: ## Instala lo necesario para el análisis (androguard)
	@pip3 install --quiet --upgrade androguard && python3 -c "import androguard;print('androguard',androguard.__version__)"

# ------------------------------------------------------------------ saneado

.PHONY: sanitize
sanitize: ## Comprueba que no se versionan secretos ni datos personales de terceros
	@bash analysis/scripts/sanitize.sh

.PHONY: hooks
hooks: ## Instala el hook de pre-commit que ejecuta sanitize
	@bash analysis/scripts/sanitize.sh --install-hook

# -------------------------------------------------------------------- Flutter

.PHONY: client-deps
client-deps: ## flutter pub get en client/
	@command -v flutter >/dev/null || { echo "falta flutter en PATH"; exit 1; }
	@cd $(CLIENT) && flutter pub get

.PHONY: client-run
client-run: ## flutter run -d chrome
	@cd $(CLIENT) && flutter run -d chrome --dart-define=BACKEND_URL=http://localhost:$(API_PORT)

.PHONY: client-apk
client-apk: ## flutter build apk --release
	@cd $(CLIENT) && flutter build apk --release

# -------------------------------------------------------------------- GitHub

.PHONY: push
push: ## Crea/sube el repo en GitHub (usa GITHUB_TOKEN o gh auth)
	@bash push.sh "$(REPO)"

.PHONY: init-git
init-git: ## git init + primer commit (sin subir)
	@git init -q -b main 2>/dev/null || true
	@git add -A && git -c user.name='dramalive-analysis' -c user.email='noreply@localhost' commit -q -m 'chore: scaffold inicial' || echo "nada que commitear"
	@git log --oneline | head -5
