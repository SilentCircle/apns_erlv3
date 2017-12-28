.PHONY: compile ct dialyzer docclean distclean docs xref clean

REBAR_PROFILE ?= default
THIS_MAKEFILE := $(lastword $(MAKEFILE_LIST))

$(info $(THIS_MAKEFILE) is using REBAR_PROFILE=$(REBAR_PROFILE))

REBAR3_URL = https://s3.amazonaws.com/rebar3/rebar3

# If there is a rebar in the current directory, use it
ifeq ($(wildcard rebar3),rebar3)
REBAR = $(CURDIR)/rebar3
endif

# Fallback to rebar on PATH
REBAR ?= $(shell which rebar3)

# And finally, prep to download rebar if all else fails
ifeq ($(REBAR),)
REBAR = $(CURDIR)/rebar3
endif

all: compile

compile: $(REBAR)
	$(REBAR) do clean, compile

clean: docclean
	$(REBAR) clean

ct: $(REBAR)
	@echo CT_EXTRA_OPTS: $(CT_EXTRA_OPTS)
	$(REBAR) do clean, ct $(CT_EXTRA_OPTS) --cover

dialyzer: $(REBAR)
	$(REBAR) dialyzer

docclean:
	@rm -rf doc/*.html doc/edoc-info html/

distclean: clean
	@rm -rf _build logs .test
	@rm -rf doc/*.html doc/edoc-info html/

docs: $(REBAR)
	$(REBAR) edoc

xref: $(REBAR)
	$(REBAR) xref

$(REBAR):
	curl -s -Lo rebar3 $(REBAR3_URL) || wget $(REBAR3_URL)
	chmod a+x $(REBAR)

