.PHONY: all build test app run install clean cert

all: test app

build:
	swift build

test:
	swift run MacToysSelfTest

app:
	./Scripts/bundle.sh release

run: app
	@pkill -x MacToys 2>/dev/null || true
	open dist/MacToys.app

install: app
	@pkill -x MacToys 2>/dev/null || true
	rm -rf /Applications/MacToys.app
	cp -R dist/MacToys.app /Applications/
	@echo "Installed to /Applications/MacToys.app"

cert:
	./Scripts/create-signing-identity.sh

clean:
	rm -rf .build dist
