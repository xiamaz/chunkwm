BUILD_FLAGS		= -O0 -g -DCHUNKWM_DEBUG -DCHUNKWM_PROFILE -std=c++11 -Wall -Wno-deprecated -Wno-writable-strings
BUILD_PATH		= ./../../../plugins
SRC				= ./plugin.mm
BINS			= $(BUILD_PATH)/monitors.so
LINK			= -shared -fPIC -framework Carbon -framework Cocoa -framework ApplicationServices

all: $(BINS)

install: BUILD_FLAGS=-O2 -std=c++11 -Wall -Wno-deprecated -Wno-writable-strings
install: clean $(BINS)

.PHONY: all clean install

$(BUILD_PATH):
	mkdir -p $(BUILD_PATH)

clean:
	rm -f $(BUILD_PATH)/monitors.so

$(BUILD_PATH)/monitors.so: $(SRC) | $(BUILD_PATH)
	clang++ $^ $(BUILD_FLAGS) -o $@ $(LINK)
