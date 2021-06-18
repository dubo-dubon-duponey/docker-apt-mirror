ARG           FROM_IMAGE_BUILDER=ghcr.io/dubo-dubon-duponey/base:builder-bullseye-2021-06-01@sha256:addbd9b89d8973df985d2d95e22383961ba7b9c04580ac6a7f406a3a9ec4731e
ARG           FROM_IMAGE_RUNTIME=ghcr.io/dubo-dubon-duponey/base:runtime-bullseye-2021-06-01@sha256:a2b1b2f69ed376bd6ffc29e2d240e8b9d332e78589adafadb84c73b778e6bc77

#######################
# Extra builder for healthchecker
#######################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-healthcheck

ARG           GIT_REPO=github.com/dubo-dubon-duponey/healthcheckers
ARG           GIT_VERSION=51ebf8c
ARG           GIT_COMMIT=51ebf8ca3d255e0c846307bf72740f731e6210c3
ARG           GO_BUILD_SOURCE=./cmd/http
ARG           GO_BUILD_OUTPUT=http-health
ARG           GO_LD_FLAGS="-s -w"
ARG           GO_TAGS="netgo osusergo"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"

#######################
# Goello
#######################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-goello

ARG           GIT_REPO=github.com/dubo-dubon-duponey/goello
ARG           GIT_VERSION=3799b60
ARG           GIT_COMMIT=3799b6035dd5c4d5d1c061259241a9bedda810d6
ARG           GO_BUILD_SOURCE=./cmd/server
ARG           GO_BUILD_OUTPUT=goello-server
ARG           GO_LD_FLAGS="-s -w"
ARG           GO_TAGS="netgo osusergo"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"

#######################
# Caddy
#######################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-caddy

# This is 2.4.0
ARG           GIT_REPO=github.com/caddyserver/caddy
ARG           GIT_VERSION=v2.4.0
ARG           GIT_COMMIT=bc2210247861340c644d9825ac2b2860f8c6e12a
ARG           GO_BUILD_SOURCE=./cmd/caddy
ARG           GO_BUILD_OUTPUT=caddy
ARG           GO_LD_FLAGS="-s -w"
ARG           GO_TAGS="netgo osusergo"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"

#######################
# Main builder
#######################
FROM          --platform=$BUILDPLATFORM $FROM_IMAGE_BUILDER                                                             AS builder-main

# April 2021 for minor fixes
ARG           GIT_REPO=github.com/aptly-dev/aptly
ARG           GIT_VERSION=f9d08e1
ARG           GIT_COMMIT=f9d08e1377970d2b13410da3d1d452b935041a4e

ARG           GO_BUILD_SOURCE=./main.go
ARG           GO_BUILD_OUTPUT=aptly
ARG           GO_LD_FLAGS="-s -w -X main.Version=$GIT_VERSION"
ARG           GO_TAGS="netgo osusergo"

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone --recurse-submodules git://"$GIT_REPO" . && git checkout "$GIT_COMMIT"
ARG           GOOS="$TARGETOS"
ARG           GOARCH="$TARGETARCH"

# hadolint ignore=SC2046
RUN           env GOARM="$(printf "%s" "$TARGETVARIANT" | tr -d v)" go build -trimpath $(if [ "$CGO_ENABLED" = 1 ]; then printf "%s" "-buildmode pie"; fi) \
                -ldflags "$GO_LD_FLAGS" -tags "$GO_TAGS" -o /dist/boot/bin/"$GO_BUILD_OUTPUT" "$GO_BUILD_SOURCE"

#######################
# Builder assembly
#######################
FROM          $FROM_IMAGE_BUILDER                                                                                       AS builder

COPY          --from=builder-healthcheck /dist/boot/bin /dist/boot/bin
COPY          --from=builder-goello /dist/boot/bin /dist/boot/bin
COPY          --from=builder-caddy /dist/boot/bin /dist/boot/bin
COPY          --from=builder-main /dist/boot/bin /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot/bin -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
FROM          $FROM_IMAGE_RUNTIME                                                                                       AS runtime

USER          root

# Aptly need these
RUN           --mount=type=secret,mode=0444,id=CA,dst=/etc/ssl/certs/ca-certificates.crt \
              --mount=type=secret,id=CERTIFICATE \
              --mount=type=secret,id=KEY \
              --mount=type=secret,id=PASSPHRASE \
              --mount=type=secret,mode=0444,id=GPG.gpg \
              --mount=type=secret,id=NETRC \
              --mount=type=secret,id=APT_SOURCES \
              --mount=type=secret,id=APT_OPTIONS,dst=/etc/apt/apt.conf.d/dbdbdp.conf \
              apt-get update -qq && \
              apt-get install -qq --no-install-recommends \
                bzip2=1.0.8-4 \
                xz-utils=5.2.5-2 \
                gnupg=2.2.27-2 && \
              apt-get -qq autoremove      && \
              apt-get -qq clean           && \
              rm -rf /var/lib/apt/lists/* && \
              rm -rf /tmp/*               && \
              rm -rf /var/tmp/*

USER          dubo-dubon-duponey

COPY          --from=builder --chown=$BUILD_UID:root /dist /

# Which architectures to mirror
ENV           ARCHITECTURES=armel,armhf,arm64,amd64,s390x,ppc64el,i386

### Front server configuration
# Port to use
ENV           PORT=4443
EXPOSE        4443
# Log verbosity for
ENV           LOG_LEVEL="warn"
# Domain name to serve
ENV           DOMAIN="apt-mirror.local"
# Control wether tls is going to be "internal" (eg: self-signed), or alternatively an email address to enable letsencrypt
ENV           TLS="internal"

# Realm in case access is authenticated
ENV           REALM="My Precious Realm"
# Provide username and password here (call the container with the "hash" command to generate a properly encrypted password, otherwise, a random one will be generated)
ENV           USERNAME=""
ENV           PASSWORD=""

### mDNS broadcasting
# Enable/disable mDNS support
ENV           MDNS_ENABLED=false
# Name is used as a short description for the service
ENV           MDNS_NAME="Aptly mDNS display name"
# The service will be annonced and reachable at $MDNS_HOST.local
ENV           MDNS_HOST="apt-mirror"
# Type to advertise
ENV           MDNS_TYPE="_http._tcp"

# Caddy certs will be stored here
VOLUME        /certs

# Caddy uses this
VOLUME        /tmp

# Aptly uses this
VOLUME        /data

ENV           HEALTHCHECK_URL="http://127.0.0.1:10000/?healthcheck"

HEALTHCHECK   --interval=120s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1

# With the final script:
# CONFIG_LOCATION=/config/aptly.conf KEYRING_LOCATION=/data/aptly/gpg/trustedkeys.gpg ARCHITECTURES=amd64 ./test.sh trust keys.gnupg.net 04EE7237B7D453EC 648ACFD622F3D138 EF0F382A1A7B6500 DCC9EFBF77E11517 AA8E81B4331F7F50 112695A0E562B32A
# CONFIG_LOCATION=/config/aptly.conf KEYRING_LOCATION=/data/aptly/gpg/trustedkeys.gpg ARCHITECTURES=amd64 ./test.sh aptly mirror create buster-updates http://deb.debian.org/debian buster-updates main


# With aptly
# gpg --no-default-keyring --keyring trustedkeys.gpg --keyserver keys.gnupg.net --recv-keys AA8E81B4331F7F50 112695A0E562B32A
# aptly -gpg-provider=internal -architectures=amd64,arm64,armel,armhf mirror create debian-security http:// buster/updates main
# aptly mirror update debian-security
# aptly snapshot create debian-security-2020-08-10 from mirror debian-security
# aptly publish snapshot debian-security-2020-08-10 buster/updates:archive/debian-security/20200801T000000Z

# aptly publish snapshot debian-security-2020-08-10 :archive/debian-security/20200810T000000Z


# deb http://snapshot.debian.org/archive/debian/20200607T000000Z buster main
#deb http://deb.debian.org/debian buster main
# deb http://snapshot.debian.org/archive/debian-security/20200607T000000Z buster/updates main
#deb http://security.debian.org/debian-security buster/updates main
# deb http://snapshot.debian.org/archive/debian/20200607T000000Z buster-updates main
#deb http://deb.debian.org/debian buster-updates main

# All in
# gpg --no-default-keyring --keyring trustedkeys.gpg --keyserver keys.gnupg.net --recv-keys EF0F382A1A7B6500 DCC9EFBF77E11517
# aptly -architectures=amd64,arm64,armel,armhf mirror create buster http://deb.debian.org/debian buster main

# gpg --no-default-keyring --keyring trustedkeys.gpg --keyserver keys.gnupg.net --recv-keys 04EE7237B7D453EC 648ACFD622F3D138
# aptly -architectures=amd64,arm64,armel,armhf mirror create buster-updates http://deb.debian.org/debian buster-updates main

# gpg --no-default-keyring --keyring trustedkeys.gpg --keyserver keys.gnupg.net --recv-keys AA8E81B4331F7F50 112695A0E562B32A
# aptly -architectures=amd64,arm64,armel,armhf mirror create buster-security http://security.debian.org/debian-security buster/updates main

# aptly mirror update buster
# aptly mirror update buster-updates
# aptly mirror update buster-security

# aptly snapshot create buster-2020-08-10 from mirror buster
# aptly snapshot create buster-updates-2020-08-10 from mirror buster-updates
# aptly snapshot create buster-security-2020-08-10 from mirror buster-security

# gpg --gen-key
# aptly -skip-signing publish snapshot buster-updates-2020-08-10 :archive/debian/20200810T000000Z

# aptly serve


# gpg --output public.pgp --armor --export foo@bar.com
# apt-key add yak.pgp


#############################
# Key generation part
#############################
# gpg --gen-key
# gpg --output public.pgp --armor --export dubo-dubon-duponey@farcloser.world
# gpg --output private.pgp --armor --export-secret-key dubo-dubon-duponey@farcloser.world

#############################
# Initialization
#############################
# gpg --no-default-keyring --keyring /data/aptly/gpg/trustedkeys.gpg --keyserver pool.sks-keyservers.net --recv-keys 04EE7237B7D453EC 648ACFD622F3D138 EF0F382A1A7B6500 DCC9EFBF77E11517 AA8E81B4331F7F50 112695A0E562B32A
# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly.conf -architectures=amd64,arm64,armel,armhf mirror create buster http://deb.debian.org/debian buster main
# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly.conf -architectures=amd64,arm64,armel,armhf mirror create buster-updates http://deb.debian.org/debian buster-updates main
# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly.conf -architectures=amd64,arm64,armel,armhf mirror create buster-security http://security.debian.org/debian-security buster/updates main

#############################
# Recurring at DATE=YYYY-MM-DD
#############################
# SUITE=buster
# DATE="$(date +%Y-%m-%d)"
# LONG_DATE="$(date +%Y%m%dT000000Z)"

# Update the mirrors
# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly.conf mirror update $SUITE
# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly.conf mirror update $SUITE-updates
# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly.conf mirror update $SUITE-security

# Create snapshots
# aptly -config /config/aptly.conf snapshot create $SUITE-$DATE from mirror $SUITE
# aptly -config /config/aptly.conf snapshot create $SUITE-updates-$DATE from mirror $SUITE-updates
# aptly -config /config/aptly.conf snapshot create $SUITE-security-$DATE from mirror $SUITE-security

# Publish snaps
# gpg --no-default-keyring --keyring /data/aptly/gpg/trustedkeys.gpg --import /data/aptly/gpg/private.pgp
# Just force gpg to preconfig
# gpg --no-default-keyring --keyring /data/aptly/gpg/trustedkeys.gpg --list-keys>

# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly.conf publish snapshot $SUITE-$DATE :archive/debian/$LONG_DATE
# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly.conf publish snapshot $SUITE-updates-$DATE :archive/debian/$LONG_DATE
# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly.conf publish snapshot $SUITE-security-$DATE :archive/debian-security/$LONG_DATE

# XXX aptly serve - use straight caddy from files instead
# move to https meanwhile
# add authentication
# deliver the public key as part of the filesystem
# On the receiving end
# echo "$GPG_PUB" | apt-key add
# apt-get -o Dir::Etc::SourceList=/dev/stdin update

# XXX to remove: aptly -config /config/aptly.conf publish drop buster-updates :archive/debian/$LONG_DATE
