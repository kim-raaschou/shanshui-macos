APP = build/Shan Shui.app
SAVER = build/Shan Shui.saver
CORE = $(wildcard Sources/Core/*.swift)
SWIFTC = swiftc -O -swift-version 5 -target arm64-apple-macos14 -import-objc-header Sources/Core/paint.h

.PHONY: all app saver install run clean test painter landscapes bench release cask

all: app saver

build/paint.o: Sources/Core/paint.c Sources/Core/paint.h
	mkdir -p build
	clang -O3 -Wall -Wextra -target arm64-apple-macos14 -c $< -o $@

build/ShanShui: $(CORE) $(wildcard Sources/App/*.swift) build/paint.o
	$(SWIFTC) -module-name ShanShui $^ -o $@

build/ShanShuiSaver: $(CORE) $(wildcard Sources/Saver/*.swift) build/paint.o
	$(SWIFTC) -module-name ShanShuiSaver -parse-as-library -emit-library -Xlinker -bundle $^ -o $@

app: build/ShanShui
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp build/ShanShui "$(APP)/Contents/MacOS/ShanShui"
	cp Resources/Info.plist "$(APP)/Contents/Info.plist"
	cp LICENSE THIRD-PARTY.md "$(APP)/Contents/Resources/"
	codesign --force --sign - "$(APP)"

saver: build/ShanShuiSaver
	rm -rf "$(SAVER)"
	mkdir -p "$(SAVER)/Contents/MacOS" "$(SAVER)/Contents/Resources"
	cp build/ShanShuiSaver "$(SAVER)/Contents/MacOS/ShanShui"
	cp Resources/Saver-Info.plist "$(SAVER)/Contents/Info.plist"
	cp LICENSE THIRD-PARTY.md "$(SAVER)/Contents/Resources/"
	codesign --force --sign - "$(SAVER)"

install: app saver
	rm -rf "/Applications/Shan Shui.app"
	cp -R "$(APP)" "/Applications/Shan Shui.app"
	mkdir -p "$(HOME)/Library/Screen Savers"
	rm -rf "$(HOME)/Library/Screen Savers/Shan Shui.saver"
	cp -R "$(SAVER)" "$(HOME)/Library/Screen Savers/Shan Shui.saver"

run: install
	open "/Applications/Shan Shui.app"

# The kernel against the shader, pixel by pixel; then the landscapes.
test: painter landscapes

painter:
	mkdir -p build
	clang -O1 -g -fsanitize=address,undefined -fno-sanitize-recover=undefined -Wall -Wextra -I Sources/Core Tests/paint.c Sources/Core/paint.c -o build/test
	build/test 30

# The generator's landscapes against their fingerprints (Tests/landscapes/fingerprints.txt).
landscapes:
	mkdir -p build
	swiftc -O -swift-version 5 Sources/Core/JSNumbers.swift Sources/Core/ShanShui*.swift Tests/landscapes/*.swift -o build/landscapes
	build/landscapes

bench:
	mkdir -p build
	clang -O3 -I Sources/Core Tests/paint.c Sources/Core/paint.c -o build/bench
	build/bench 240

# The release zip: the app and the screen saver side by side.
VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
ZIP := dist/ShanShui-$(VERSION).zip

release: app saver
	codesign --verify --strict "$(APP)"
	codesign --verify --strict "$(SAVER)"
	rm -rf dist/zip $(ZIP)
	mkdir -p dist/zip
	cp -R "$(APP)" "$(SAVER)" dist/zip/
	@# No ._ files (extended attributes): unzip would add them to the bundles and break
	@# their signatures.
	ditto -c -k --norsrc --noextattr dist/zip $(ZIP)
	rm -rf dist/zip
	@shasum -a 256 $(ZIP)

# The Homebrew cask for the release zip (kim-raaschou/homebrew-tap: Casks/shanshui.rb).
# The release is tagged v$(VERSION) on GitHub, with $(ZIP) attached.
cask:
	@test -f $(ZIP) || { echo "error: no $(ZIP); run make release first"; exit 1; }
	sed -e "s/@VERSION@/$(VERSION)/" -e "s/@SHA256@/$$(shasum -a 256 $(ZIP) | cut -d' ' -f1)/" \
		Resources/shanshui.rb.in > dist/shanshui.rb
	@echo "wrote dist/shanshui.rb"

clean:
	rm -rf build dist
