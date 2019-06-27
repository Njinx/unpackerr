# binary name.
BINARY:=unpacker-poller
URL:=https://github.com/davidnewhall/$(BINARY)
MAINT=David Newhall II <david at sleepers dot pro>
DESC=Extracts Deluge downloads so Radarr or Sonarr may import them.
GOLANGCI_LINT_ARGS=--enable-all -D gochecknoglobals -D lll
DOCKER_REPO=golift
MD2ROFF_BIN=github.com/github/hub/md2roff-bin

# used for plist file name on macOS.
ID=com.github.davidnewhall

# These don't generally need to be changed.
ITERATION:=$(shell git rev-list --count HEAD || echo 0)
ifeq ($(VERSION),)
	VERSION:=$(shell git tag -l --merged | tail -n1 | tr -d v || echo development)
endif
# rpm is wierd and changes - to _ in versions.
RPMVERSION:=$(shell echo $(VERSION) | tr -- - _)

all: test man build
	@echo Finished.

# Delete all build assets.
clean:
	# Cleaning up.
	rm -f $(BINARY){.macos,.linux,.1.gz,.exe,.rb} $(BINARY){_,-}*.{deb,rpm}
	rm -f examples/MANUAL ./$(BINARY).html README{,.html} v*.tar.gz.sha256
	rm -rf package_build_* release

build:
	@echo "Building Binary"
	go build -ldflags "-w -s"

# Used for Homebrew only. Other disros can create packages.
install: man readme $(BINARY)
	@echo -  Done Building!  -
	@echo -  Local installation with the Makefile is only supported on macOS.
	@echo If you wish to install the application manually on Linux, download a package.
	@echo -  Otherwise, build and install a package: make rpm -or- make deb
	@[ "$(shell uname)" = "Darwin" ] || (echo "Unable to continue, not a Mac." && false)
	@[ "$(PREFIX)" != "" ] || (echo "Unable to continue, PREFIX not set. Use: make install PREFIX=/usr/local ETC=/usr/local/etc" && false)
	@[ "$(ETC)" != "" ] || (echo "Unable to continue, ETC not set. Use: make install PREFIX=/usr/local ETC=/usr/local/etc" && false)
	# Copying the binary, config file, unit file, and man page into the env.
	/usr/bin/install -m 0755 -d $(PREFIX)/bin $(PREFIX)/share/man/man1 $(ETC)/$(BINARY) $(PREFIX)/share/doc/$(BINARY)
	/usr/bin/install -m 0755 -cp $(BINARY) $(PREFIX)/bin/$(BINARY)
	/usr/bin/install -m 0644 -cp $(BINARY).1.gz $(PREFIX)/share/man/man1
	/usr/bin/install -m 0644 -cp examples/up.conf.example $(ETC)/$(BINARY)/
	[ -f $(ETC)/$(BINARY)/up.conf ] || /usr/bin/install -m 0644 -cp  examples/up.conf.example $(ETC)/$(BINARY)/up.conf
	/usr/bin/install -m 0644 -cp LICENSE *.html examples/* $(PREFIX)/share/doc/$(BINARY)/
	# These go to their own folder so the img src in the html pages continue to work.

# Run this before you install a package.
uninstall:
	@echo "If you get errors, you may need sudo."
	test -f ~/Library/LaunchAgents/$(ID).$(BINARY).plist && launchctl unload ~/Library/LaunchAgents/$(ID).$(BINARY).plist || true
	test -f /etc/systemd/system/$(BINARY).service && systemctl stop $(BINARY) || true
	rm -rf /usr/local/{etc,bin}/$(BINARY) /usr/local/share/man/man1/$(BINARY).1.gz
	rm -f ~/Library/LaunchAgents/$(ID).$(BINARY).plist
	rm -f /etc/systemd/system/$(BINARY).service

# Prepare a release. Called in Travis CI.
release: clean vendor test macos windows $(BINARY)-$(RPMVERSION)-$(ITERATION).x86_64.rpm $(BINARY)_$(VERSION)-$(ITERATION)_amd64.deb
	# Prepareing a release!
	mkdir -p release
	mv $(BINARY).linux $(BINARY).macos release/
	gzip -9r release/
	zip -9qm release/$(BINARY).exe.zip $(BINARY).exe
	mv $(BINARY)-$(RPMVERSION)-$(ITERATION).x86_64.rpm $(BINARY)_$(VERSION)-$(ITERATION)_amd64.deb release/
	# Generating File Hashes
	for i in release/*; do /bin/echo -n "$$i " ; (openssl dgst -r -sha256 "$$i" | head -c64 ; echo) | tee "$$i.sha256.txt"; done


# Build a man page from a markdown file using md2roff.
# This also turns the repo readme into an html file.
# md2roff is needed to build the man file and html pages from the READMEs.
man: $(BINARY).1.gz
$(BINARY).1.gz: md2roff
	# Building man page. Build dependency first: md2roff
	go run $(MD2ROFF_BIN) --manual $(BINARY) --version $(VERSION) --date "$(shell date)" examples/MANUAL.md
	gzip -9nc examples/MANUAL > $(BINARY).1.gz
	mv -n examples/MANUAL.html $(BINARY).html

md2roff:
	go get $(MD2ROFF_BIN)

# TODO: provide a template that adds the date to the built html file.
readme: README.html
README.html: md2roff
	# This turns README.md into README.html
	go run $(MD2ROFF_BIN) --manual $(BINARY) --version $(VERSION) --date "$(shell date)" README.md

# Binaries

build: $(BINARY)
$(BINARY):
	go build -o $(BINARY) -ldflags "-w -s -X github.com/davidnewhall/unpacker-poller/unpackerpoller.Version=$(VERSION)"

linux: $(BINARY).linux
$(BINARY).linux:
	# Building linux binary.
	GOOS=linux go build -o $(BINARY).linux -ldflags "-w -s -X github.com/davidnewhall/unpacker-poller/unpackerpoller.Version=$(VERSION)"

macos: $(BINARY).macos
$(BINARY).macos:
	# Building darwin binary.
	GOOS=darwin go build -o $(BINARY).macos -ldflags "-w -s -X github.com/davidnewhall/unpacker-poller/unpackerpoller.Version=$(VERSION)"

exe: $(BINARY).exe
windows: $(BINARY).exe
$(BINARY).exe:
	# Building windows binary.
	GOOS=windows go build -o $(BINARY).exe -ldflags "-w -s -X github.com/davidnewhall/unpacker-poller/unpackerpoller.Version=$(VERSION)"

# Packages

rpm: $(BINARY)-$(RPMVERSION)-$(ITERATION).x86_64.rpm
$(BINARY)-$(RPMVERSION)-$(ITERATION).x86_64.rpm: check_fpm package_build_linux
	@echo "Building 'rpm' package for $(BINARY) version '$(RPMVERSION)-$(ITERATION)'."
	fpm -s dir -t rpm \
		--name $(BINARY) \
		--rpm-os linux \
		--version $(RPMVERSION) \
		--iteration $(ITERATION) \
		--after-install scripts/after-install.sh \
		--before-remove scripts/before-remove.sh \
		--license MIT \
		--url $(URL) \
		--maintainer "$(MAINT)" \
		--description "$(DESC)" \
		--chdir package_build_linux

deb: $(BINARY)_$(VERSION)-$(ITERATION)_amd64.deb
$(BINARY)_$(VERSION)-$(ITERATION)_amd64.deb: check_fpm package_build_linux
	@echo "Building 'deb' package for $(BINARY) version '$(VERSION)-$(ITERATION)'."
	fpm -s dir -t deb \
		--name $(BINARY) \
		--version $(VERSION) \
		--iteration $(ITERATION) \
		--after-install scripts/after-install.sh \
		--before-remove scripts/before-remove.sh \
		--license MIT \
		--url $(URL) \
		--maintainer "$(MAINT)" \
		--description "$(DESC)" \
		--chdir package_build_linux

docker:
	docker build -f init/docker/Dockerfile -t $(DOCKER_REPO)/$(BINARY) .

# Build an environment that can be packaged for linux.
package_build_linux: readme man linux
	# Building package environment for linux.
	mkdir -p $@/usr/bin $@/etc/$(BINARY) $@/lib/systemd/system
	mkdir -p $@/usr/share/man/man1 $@/usr/share/doc/$(BINARY)
	# Copying the binary, config file, unit file, and man page into the env.
	cp $(BINARY).linux $@/usr/bin/$(BINARY)
	cp *.1.gz $@/usr/share/man/man1
	cp examples/up.conf.example $@/etc/$(BINARY)/
	cp examples/up.conf.example $@/etc/$(BINARY)/up.conf
	cp LICENSE *.html examples/* $@/usr/share/doc/$(BINARY)/
	# These go to their own folder so the img src in the html pages continue to work.
	cp init/systemd/$(BINARY).service $@/lib/systemd/system/

check_fpm:
	@fpm --version > /dev/null || (echo "FPM missing. Install FPM: https://fpm.readthedocs.io/en/latest/installing.html" && false)

# This builds a Homebrew formula file that can be used to install this app from source.
formula: $(BINARY).rb
v$(VERSION).tar.gz.sha256:
	# Calculate the SHA from the Github source file.
	curl -sL $(URL)/archive/v$(VERSION).tar.gz | openssl dgst -r -sha256 | tee v$(VERSION).tar.gz.sha256
$(BINARY).rb: v$(VERSION).tar.gz.sha256
	# Creating formula from template using sed.
	sed "s/{{Version}}/$(VERSION)/g;s/{{SHA256}}/`head -c64 v$(VERSION).tar.gz.sha256`/g;s/{{Desc}}/$(DESC)/g;s%{{URL}}%$(URL)%g" init/homebrew/$(BINARY).rb.tmpl | tee $(BINARY).rb

# Run code tests and lint.
test: lint
	# Testing.
	go test -race -covermode=atomic ./...
lint:
	# Checking lint.
	golangci-lint run $(GOLANGCI_LINT_ARGS)

# This is safe; recommended even.
dep: vendor
vendor:
	dep ensure --vendor-only

# Don't run this unless you're ready to debug untested vendored dependencies.
deps:
	dep ensure --update