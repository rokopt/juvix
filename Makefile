PWD=$(CURDIR)
PREFIX="$(PWD)/.stack-work/prefix"
UNAME := $(shell uname)

ifeq ($(UNAME), Darwin)
	THREADS := $(shell sysctl -n hw.logicalcpu)
else ifeq ($(UNAME), Linux)
	THREADS := $(shell nproc)
else
	THREADS := $(shell echo %NUMBER_OF_PROCESSORS%)
endif

all: setup build

setup:
	stack build --only-dependencies --jobs $(THREADS)

build-libff:
	./scripts/build-libff.sh

build-z3:
	mkdir -p $(PREFIX)
	cd z3 && test -f build/Makefile || python scripts/mk_make.py -p $(PREFIX)
	cd z3/build && make -j $(PREFIX)
	cd z3/build && make install

build:
	stack build --fast --jobs $(THREADS)

build-watch:
	stack build --fast --file-watch

build-prod: clean
	stack build --jobs $(THREADS) --ghc-options="-O3" --ghc-options="-fllvm" --flag juvix:incomplete-error

build-format:
	stack install ormolu

lint:
	stack exec -- hlint app src test

format:
	find . -path ./.stack-work -prune -o -path ./archived -prune -o -type f -name "*.hs" -exec ormolu --mode inplace {} --ghc-opt -XTypeApplications --ghc-opt -XUnicodeSyntax --ghc-opt -XPatternSynonyms --ghc-opt -XTemplateHaskell \;

org-gen:
	org-generation app/ doc/Code/App.org test/ doc/Code/Test.org src/ doc/Code/Juvix.org bench/ doc/Code/Bench.org library/ doc/Code/Library.org

test:
	stack test --fast --jobs=$(THREADS) --test-arguments "--hide-successes --ansi-tricks false"

test-parser: build
	find test/examples/positive/michelson/demo -name "*.ju" | xargs -t -n 1 -I % stack exec juvix -- parse % -b "michelson"

test-typecheck: build
	find test/examples/positive/michelson/demo -name "*.ju" | xargs -t -n 1 -I % stack exec juvix -- typecheck % -b "michelson"

test-compile: build
	find test/examples/positive/michelson/demo -name "*.ju" | xargs -n 1 -I % basename % .ju | xargs -t -n 1 -I % stack exec juvix -- compile test/examples/positive/michelson/demo/%.ju test/examples/positive/michelson/demo/%.tz -b "michelson"
	rm test/examples/positive/michelson/demo/*.tz

bench:
	stack bench --benchmark-arguments="--output ./doc/Code/bench.html"

repl-lib:
	stack ghci juvix:lib

repl-exe:
	stack ghci juvix:exe:juvix

clean:
	stack clean

clean-full:
	stack clean --full

stack-yaml:
	ros -Q scripts/yaml-generator/yaml-generator.asd

# Overwrite existing golden files
accept-golden:
	stack test --test-arguments "--accept"


.PHONY: all setup build build-libff build-z3 build-watch build-prod lint format org-gen test test-parser test-typecheck test-compile repl-lib repl-exe clean clean-full bench build-format
