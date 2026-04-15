CC ?= clang
BUILD_DIR ?= build
DESTDIR ?=

DYLIB := $(BUILD_DIR)/nimo.dylib
TEST_BIN := $(BUILD_DIR)/test_nimo

CFLAGS_COMMON := -O2 -Wall -Wextra -fPIC -mmacosx-version-min=12.0
CFLAGS_UNIVERSAL := -arch arm64 -arch x86_64
LDFLAGS_DYLIB := -dynamiclib -install_name @rpath/nimo.dylib

.PHONY: all test clean

all: $(DYLIB)

$(DYLIB): nimo.c | $(BUILD_DIR)
	$(CC) $(CFLAGS_UNIVERSAL) $(CFLAGS_COMMON) $(LDFLAGS_DYLIB) -o $(DESTDIR)$@ nimo.c

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

test: $(TEST_BIN)
	$(TEST_BIN)

$(TEST_BIN): tests/test_nimo.c nimo.c | $(BUILD_DIR)
	$(CC) -DNIMO_TEST -O0 -g -Wall -Wextra tests/test_nimo.c -o $@

clean:
	rm -rf $(BUILD_DIR)
