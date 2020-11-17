ARG           BUILDER_BASE=dubodubonduponey/base@sha256:b51f084380bc1bd2b665840317b6f19ccc844ee2fc7e700bf8633d95deba2819
ARG           RUNTIME_BASE=dubodubonduponey/base@sha256:d28e8eed3e87e8dc5afdd56367d3cf2da12a0003d064b5c62405afbe4725ee99

#######################
# Extra builder for healthchecker
#######################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-healthcheck

ARG           GIT_REPO=github.com/dubo-dubon-duponey/healthcheckers
ARG           GIT_VERSION=51ebf8ca3d255e0c846307bf72740f731e6210c3

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w" \
                -o /dist/boot/bin/http-health ./cmd/http

#######################
# Goello
#######################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-goello

ARG           GIT_REPO=github.com/dubo-dubon-duponey/goello
ARG           GIT_VERSION=6f6c96ef8161467ab25be45fe3633a093411fcf2

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w" \
                -o /dist/boot/bin/goello-server ./cmd/server/main.go

#######################
# Aptly
#######################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-aptly

# XXX is this abandonned? Has not been updated in over a year
ARG           GIT_REPO=github.com/aptly-dev/aptly
ARG           GIT_VERSION=24a027194ea8818307083396edb76565f41acc92

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone git://$GIT_REPO .
RUN           git checkout $GIT_VERSION
# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w -X main.Version=$BUILD_VERSION" \
                -o /dist/boot/bin/aptly ./main.go

#######################
# Caddy
#######################
# hadolint ignore=DL3006
FROM          --platform=$BUILDPLATFORM $BUILDER_BASE                                                                   AS builder-caddy

# This is 2.2.1 (11/16/2020)
ARG           GIT_REPO=github.com/caddyserver/caddy
ARG           GIT_VERSION=385adf5d878939c381c7f73c771771d34523a1a7

WORKDIR       $GOPATH/src/$GIT_REPO
RUN           git clone https://$GIT_REPO .
RUN           git checkout $GIT_VERSION

# hadolint ignore=DL4006
RUN           env GOOS=linux GOARCH="$(printf "%s" "$TARGETPLATFORM" | sed -E 's/^[^/]+\/([^/]+).*/\1/')" go build -v -ldflags "-s -w" \
                -o /dist/boot/bin/caddy ./cmd/caddy

#######################
# Builder assembly
#######################
# hadolint ignore=DL3006
FROM          $BUILDER_BASE                                                                                             AS builder

COPY          --from=builder-healthcheck /dist/boot/bin /dist/boot/bin
COPY          --from=builder-aptly /dist/boot/bin /dist/boot/bin
COPY          --from=builder-caddy /dist/boot/bin /dist/boot/bin
COPY          --from=builder-goello /dist/boot/bin /dist/boot/bin

RUN           chmod 555 /dist/boot/bin/*; \
              epoch="$(date --date "$BUILD_CREATED" +%s)"; \
              find /dist/boot/bin -newermt "@$epoch" -exec touch --no-dereference --date="@$epoch" '{}' +;

#######################
# Running image
#######################
# hadolint ignore=DL3006
FROM          $RUNTIME_BASE                                                                                             AS runtime

USER          root

#                nano \
RUN           apt-get update -qq          && \
              apt-get install -qq --no-install-recommends \
                bzip2=1.0.6-9.2~deb10u1 \
                xz-utils=5.2.4-1 \
                gnupg=2.2.12-1+deb10u1 && \
              apt-get -qq autoremove      && \
              apt-get -qq clean           && \
              rm -rf /var/lib/apt/lists/* && \
              rm -rf /tmp/*               && \
              rm -rf /var/tmp/*

USER          dubo-dubon-duponey

COPY          --from=builder --chown=$BUILD_UID:root /dist .

EXPOSE        8080/tcp

VOLUME        /data
VOLUME        /tmp

ENV           ARCHITECTURES=armel,armhf,arm64,amd64,s390x,ppc64el

# mDNS
ENV           MDNS_NAME="Fancy Apt Mirror Service Name"
ENV           MDNS_HOST="apt-mirror"
ENV           MDNS_TYPE=_apt._tcp

# Authentication
ENV           USERNAME="dubo-dubon-duponey"
ENV           PASSWORD="base64_bcrypt_encoded_use_caddy_hash_password_to_generate"
ENV           REALM="My precious mirror"

# Log level and port
ENV           LOG_LEVEL=info
ENV           PORT=8080

# System constants, unlikely to ever require modifications in normal use
ENV           HEALTHCHECK_URL=http://127.0.0.1:10042/healthcheck

HEALTHCHECK   --interval=30s --timeout=30s --start-period=10s --retries=1 CMD http-health || exit 1

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
