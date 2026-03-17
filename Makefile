ESSENTIA_INCLUDE ?= /usr/local/include
ESSENTIA_LIB ?= /usr/local/lib
HOMEBREW_PREFIX ?= $(shell brew --prefix 2>/dev/null || echo /opt/homebrew)

ERTS_INCLUDE_DIR ?= $(shell erl -eval 'io:format("~s~n", [lists:concat([code:root_dir(), "/erts-", erlang:system_info(version), "/include"])])' -s init stop -noshell)

# Add the -v flag to CXX to get more verbose output
EIGEN_CFLAGS ?= $(shell pkg-config --cflags eigen3)

CXXFLAGS = -std=c++14 -O3 -fPIC -I$(ESSENTIA_INCLUDE) -I$(HOMEBREW_PREFIX)/include $(EIGEN_CFLAGS) -I$(ERTS_INCLUDE_DIR)
LDFLAGS = -shared -L$(ESSENTIA_LIB) -L$(HOMEBREW_PREFIX)/lib -lessentia -lfftw3f -lfftw3 -lyaml -lavcodec -lavformat -lavutil -lsamplerate -ltag

ifeq ($(shell uname -s), Darwin)
	LDFLAGS += -undefined dynamic_lookup -rpath $(HOMEBREW_PREFIX)/lib
endif

# Check whether Essentia headers are present before attempting to compile
ESSENTIA_HEADER := $(ESSENTIA_INCLUDE)/essentia/essentia.h
ESSENTIA_FOUND := $(shell test -f "$(ESSENTIA_HEADER)" && echo yes || echo no)

.PHONY: all clean debug

ifeq ($(ESSENTIA_FOUND), yes)
all: priv/essentia_nif.so

priv/essentia_nif.so: c_src/essentia_nif.cpp
	mkdir -p priv
	$(CXX) $(CXXFLAGS) -o $@ $< $(LDFLAGS)
else
all:
	@echo "---"
	@echo "WARNING: Essentia headers not found at $(ESSENTIA_HEADER)"
	@echo "The NIF will not be compiled. Audio analysis functions will"
	@echo "raise :nif_not_loaded until Essentia is installed."
	@echo "See https://essentia.upf.edu/installing.html"
	@echo "---"
endif

clean:
	rm -f priv/essentia_nif.so

# Add a debug target
debug:
	@echo "ESSENTIA_INCLUDE = $(ESSENTIA_INCLUDE)"
	@echo "ESSENTIA_LIB = $(ESSENTIA_LIB)"
	@echo "HOMEBREW_PREFIX = $(HOMEBREW_PREFIX)"
	@echo "ESSENTIA_FOUND = $(ESSENTIA_FOUND)"
	@echo "ERTS_INCLUDE_DIR = $(ERTS_INCLUDE_DIR)"
	@echo "CXXFLAGS = $(CXXFLAGS)"
	@echo "LDFLAGS = $(LDFLAGS)"
