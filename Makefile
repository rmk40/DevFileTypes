APP_NAME    := DevFileTypes
APP_BUNDLE  := $(APP_NAME).app
CONTENTS    := $(APP_BUNDLE)/Contents
MACOS_DIR   := $(CONTENTS)/MacOS
EXECUTABLE  := $(MACOS_DIR)/$(APP_NAME)
PLIST       := $(CONTENTS)/Info.plist

CC          := cc
CFLAGS      := -O2

# Build the app bundle with a fresh executable from source
.PHONY: all clean

all: $(EXECUTABLE)

$(EXECUTABLE): main.c $(PLIST) | $(MACOS_DIR)
	$(CC) $(CFLAGS) -o $@ $<

$(MACOS_DIR):
	mkdir -p $(MACOS_DIR)

# Rebuild the executable only (Info.plist is maintained by hand)
clean:
	rm -f $(EXECUTABLE)
