# Build the native SubProcess spawn shim and its self-test.
# Targets:
#   all   : build libsps_spawn (shared lib) + the self-test binary
#   selftest : build and run the self-test
#   clean : remove build artifacts
#
# Unix/macOS:  make            (uses cc)
# Windows:     use mingw32-make CC=gcc (MinGW toolchain); produces sps_spawn.dll

UNAME_S := $(shell uname -s)

# On Windows the "shim" is a DLL that Pharo loads via FFI.
ifeq ($(OS),Windows_NT)
TARGET      = sps_spawn.dll
SELFTEST    = sps_spawn_selftest.exe
POSIX_SRC   =
WIN_SRC     = sps_spawn_win.c
WIN_FLAGS   = -D_WIN32_WINNT=0x0601
else ifeq ($(UNAME_S),Darwin)
TARGET      = libsps_spawn.dylib
SELFTEST    = sps_spawn_selftest
POSIX_SRC   = sps_spawn_posix.c
WIN_SRC     =
WIN_FLAGS   =
else
TARGET      = libsps_spawn.so
SELFTEST    = sps_spawn_selftest
POSIX_SRC   = sps_spawn_posix.c
WIN_SRC     =
WIN_FLAGS   =
endif

CC        ?= cc
CFLAGS     = -Wall -Wextra -O2 -std=c99 -fPIC $(WIN_FLAGS)
LDLIBS     =

ifeq ($(OS),Windows_NT)
LDLIBS    += -luser32 -ladvapi32 -lkernel32
endif

.PHONY: all selftest clean

all: $(TARGET)

# Shared library consumed by the Pharo SubProcess package.
$(TARGET): sps_spawn.h sps_spawn_args.h $(POSIX_SRC) sps_spawn_args.c $(WIN_SRC)
	$(CC) $(CFLAGS) -shared \
	    $(POSIX_SRC) sps_spawn_args.c $(WIN_SRC) -o $(TARGET) $(LDLIBS)

# Standalone binary exercising the shim end-to-end (no GLib).
$(SELFTEST): sps_spawn.h sps_spawn_args.h $(POSIX_SRC) sps_spawn_args.c $(WIN_SRC) sps_spawn_selftest.c
	$(CC) $(CFLAGS) \
	    $(POSIX_SRC) sps_spawn_args.c $(WIN_SRC) sps_spawn_selftest.c -o $(SELFTEST) $(LDLIBS)

selftest: $(SELFTEST)
	./$(SELFTEST)

clean:
	rm -f $(TARGET) $(SELFTEST)
