.PHONY: docs

EDOWN_TOP_LEVEL_README_URL := https://code.silentcircle.org/scps/apns_erlv3
EDOWN_TARGET := stash

docs:
	$(MAKE) docs EDOWN_TOP_LEVEL_README_URL=$(EDOWN_TOP_LEVEL_README_URL) EDOWN_TARGET=$(EDOWN_TARGET)
