BUILD_FLAGS		= -O0 -g -std=c++11 -Wall
BUILD_PATH		= ./../../../plugins
SRC				= ./plugin.cpp
BINS			= $(BUILD_PATH)/subscribe.so
LINK			= -shared -fPIC -framework Carbon -framework Cocoa -framework ApplicationServices

all: $(BINS)

install: BUILD_FLAGS=-O2 -std=c++11 -Wall
install: clean $(BINS)

.PHONY: all clean install

$(BUILD_PATH):
	mkdir -p $(BUILD_PATH)

clean:
	rm -f $(BUILD_PATH)/subscribe.so

$(BUILD_PATH)/subscribe.so: $(SRC) | $(BUILD_PATH)
	clang++ $^ $(BUILD_FLAGS) -o $@ $(LINK)
