.PHONY: prove health ask stream wstest

HOST ?= https://cgptproject-web.onrender.com
TOKEN ?=

prove:
	@HOST=$(HOST) bash scripts/prove_runtime.sh

health:
	@curl -sS -i $(HOST)/health | sed -n '1,10p'

ask:
	@HOST=$(HOST) TOKEN=$(TOKEN) bash scripts/ask_json.sh

stream:
	@HOST=$(HOST) TOKEN=$(TOKEN) bash scripts/smoke.sh

wstest:
	@python -c 'import sys; print(sys.version)'
	@python -m pip install -q websocket-client
	@HOST=$(HOST) TOKEN=$(TOKEN) python scripts/ws_test.py
