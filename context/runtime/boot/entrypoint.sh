#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

[ -w /certs ] || {
  printf >&2 "/certs is not writable. Check your mount permissions.\n"
  exit 1
}

[ -w /tmp ] || {
  printf >&2 "/tmp is not writable. Check your mount permissions.\n"
  exit 1
}

[ -w /data ] || {
  printf >&2 "/data is not writable. Check your mount permissions.\n"
  exit 1
}

# Helpers
case "${1:-run}" in
  # Short hand helper to generate password hash
  "hash")
    shift
    printf >&2 "Generating password hash\n"
    caddy hash-password -algorithm bcrypt "$@"
    exit
  ;;
  # Helper to get the ca.crt out (once initialized)
  "cert")
    if [ "${TLS:-}" == "" ]; then
      printf >&2 "Your container is not configured for TLS termination - there is no local CA in that case."
      exit 1
    fi
    if [ "${TLS:-}" != "internal" ]; then
      printf >&2 "Your container uses letsencrypt - there is no local CA in that case."
      exit 1
    fi
    if [ ! -e /certs/pki/authorities/local/root.crt ]; then
      printf >&2 "No root certificate installed or generated. Run the container so that a cert is generated, or provide one at runtime."
      exit 1
    fi
    cat /certs/pki/authorities/local/root.crt
    exit
  ;;
  "run")
    # Bonjour the container if asked to. While the PORT is no guaranteed to be mapped on the host in bridge, this does not matter since mDNS will not work at all in bridge mode.
    if [ "${MDNS_ENABLED:-}" == true ]; then
      goello-server -json "$(printf '[{"Type": "%s", "Name": "%s", "Host": "%s", "Port": %s, "Text": {}}]' "$MDNS_TYPE" "$MDNS_NAME" "$MDNS_HOST" "$PORT")" &
    fi

    # If we want TLS and authentication, start caddy in the background
    if [ "${TLS:-}" ]; then
      HOME=/tmp/caddy-home caddy run -config /config/caddy/main.conf --adapter caddyfile &
    fi
  ;;
esac

# System constants
readonly ARCHITECTURES="${ARCHITECTURES:-}"

readonly CONFIG_LOCATION="${CONFIG_LOCATION:-/config/aptly/main.conf}"
readonly GPG_HOME="/data/gpg"
readonly KEYRING_LOCATION="${KEYRING_LOCATION:-$GPG_HOME/trustedkeys.gpg}"

readonly SUITE=bullseye

readonly GPG_ARGS=(--no-default-keyring --keyring "$KEYRING_LOCATION")

mkdir -p "$GPG_HOME/home"
chmod go-rwx "$GPG_HOME/home"
export GNUPGHOME="$GPG_HOME/home"


gpg::trust(){
  local server="$1"
  shift
  gpg "${GPG_ARGS[@]}" --keyserver "$server" --recv-keys "$@"
}

gpg::initialize(){
  local name="$1"
  local mail="$2"
  shift
  shift
  echo "%echo Generating a gpg signing key
%no-protection
Key-Type: default
Subkey-Type: default
Name-Real: $name
Name-Comment: Snapshot signing key
Name-Email: $mail
Expire-Date: 0
$*
%commit
%echo done" | gpg "${GPG_ARGS[@]}" --batch --generate-key /dev/stdin >/dev/null 2>&1
  gpg "${GPG_ARGS[@]}" --output "$GPG_HOME"/snapshot-signing-public-key.pgp --armor --export "$mail"
#  gpg --no-default-keyring --keyring "$GPG_HOME"/trusted-export.gpg --import "$GPG_HOME"/snapshot-signing-public-key.pgp
  printf >&2 "You need to apt-key add %s to consume this repo\n" "$GPG_HOME/snapshot-signing-public-key.pgp"
}

aptly::refresh(){
  local mirros
  local mir
  local DATE
  local LONG_DATE
  mirros="$(aptly -config="$CONFIG_LOCATION" -architectures="$ARCHITECTURES" mirror list -raw)"
  while true; do
    DATE="$(date +%Y-%m-%d)"
    LONG_DATE="$(date +%Y%m%dT000000Z)"
    for mir in $mirros; do
      printf >&2 "Updating existing mirror %s\n" "$mir"
      aptly -keyring="$KEYRING_LOCATION" -config="$CONFIG_LOCATION" -architectures="$ARCHITECTURES" mirror update "$mir"
    done

    for mir in $mirros; do
      # If we have a published snapshot at that date already, just continue
      printf >&2 "Have a published one already? If yes, continue.\n"
      ! aptly -config="$CONFIG_LOCATION" -architectures="$ARCHITECTURES" publish list --raw | grep -q "^archive/$mir/$LONG_DATE" > /dev/null || continue

      # If we don't have a snapshot, create one
      if ! aptly -config="$CONFIG_LOCATION" -architectures="$ARCHITECTURES" snapshot show "$mir-$DATE" > /dev/null; then
        printf >&2 "No snapshot yet for that date and mirror, create one.\n"
        aptly -config="$CONFIG_LOCATION" -architectures="$ARCHITECTURES" snapshot create "$mir-$DATE" from mirror "$mir" > /dev/null
      fi

      # And publish
      printf >&2 "And... publish it\n"
      aptly -keyring="$KEYRING_LOCATION" -config="$CONFIG_LOCATION" -architectures="$ARCHITECTURES" publish snapshot "$mir-$DATE" :"archive/$mir/$LONG_DATE" # > /dev/null
    done
    printf >&2 "Going to sleep for a day now\n"
    sleep 86400
  done
}

com="${1:-}"
shift || true
case "$com" in
"aptly")
  # Typically create a new mirror with:
  # aptly mirror create "$nickname" "$url" "$suite" "$component"
  aptly -config="$CONFIG_LOCATION" -architectures="$ARCHITECTURES" "$@"
  exit
  ;;
"aptly-with-keyring")
  # Typically create a new mirror with:
  # aptly mirror create "$nickname" "$url" "$suite" "$component"
  aptly -keyring="$KEYRING_LOCATION" -config="$CONFIG_LOCATION" -architectures="$ARCHITECTURES" "$@"
  exit
  ;;
"create")
  # Example: my-buster-updates-mirror http://deb.debian.org/debian buster-updates main contrib non-free
  aptly -keyring="$KEYRING_LOCATION" -config="$CONFIG_LOCATION" -architectures="$ARCHITECTURES" mirror create "$@"
  exit
  ;;
"trust")
  # Typically "key server" "keys...": keys.gnupg.net 04EE7237B7D453EC 648ACFD622F3D138 EF0F382A1A7B6500 DCC9EFBF77E11517 AA8E81B4331F7F50 112695A0E562B32A
  gpg::trust "$@"
  exit
  ;;
"init")
  # Typically "My name" "My email"
  gpg::initialize "$@"
  exit
  ;;
*)
  # Start our daily refresher
  aptly::refresh
  ;;
esac

#############################
# Key generation part
#############################
# gpg --no-default-keyring --keyring /data/aptly/gpg/trustedkeys.gpg --gen-key
# gpg --no-default-keyring --keyring /data/aptly/gpg/trustedkeys.gpg --output public.pgp --armor --export dubo-dubon-duponey@farcloser.world
# gpg --output private.pgp --armor --export-secret-key dubo-dubon-duponey@farcloser.world
# gpg --no-default-keyring --keyring /data/aptly/gpg/trustedkeys.gpg --import private.pgp

#############################
# Initialization
#############################
# gpg --no-default-keyring --keyring /data/aptly/gpg/trustedkeys.gpg --keyserver keys.openpgp.org --recv-keys 04EE7237B7D453EC 648ACFD622F3D138 EF0F382A1A7B6500 DCC9EFBF77E11517 AA8E81B4331F7F50 112695A0E562B32A
# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly/main.conf -architectures=amd64,arm64,armel,armhf mirror create buster http://deb.debian.org/debian buster main
# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly/main.conf -architectures=amd64,arm64,armel,armhf mirror create buster-updates http://deb.debian.org/debian buster-updates main
# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly/main.conf -architectures=amd64,arm64,armel,armhf mirror create buster-security http://security.debian.org/debian-security buster/updates main

#############################
# Recurring at DATE=YYYY-MM-DD
#############################
# SUITE=buster
# DATE="$(date +%Y-%m-%d)"
# LONG_DATE="$(date +%Y%m%dT000000Z)"

# Update the mirrors
# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly/main.conf mirror update $SUITE
# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly/main.conf mirror update $SUITE-updates
# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly/main.conf mirror update $SUITE-security

# Create snapshots
# aptly -config /config/aptly/main.conf snapshot create $SUITE-$DATE from mirror $SUITE
# aptly -config /config/aptly/main.conf snapshot create $SUITE-updates-$DATE from mirror $SUITE-updates
# aptly -config /config/aptly/main.conf snapshot create $SUITE-security-$DATE from mirror $SUITE-security

# Publish snaps
# gpg --no-default-keyring --keyring /data/aptly/gpg/trustedkeys.gpg --import /data/aptly/gpg/private.pgp
# Just force gpg to preconfig
# gpg --no-default-keyring --keyring /data/gpg/trustedkeys.gpg --list-keys

# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly/main.conf publish snapshot $SUITE-$DATE :archive/debian/$LONG_DATE
# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly/main.conf publish snapshot $SUITE-updates-$DATE :archive/debian/$LONG_DATE
# aptly -keyring=/data/aptly/gpg/trustedkeys.gpg -config /config/aptly/main.conf publish snapshot $SUITE-security-$DATE :archive/debian-security/$LONG_DATE

# XXX aptly serve - use straight caddy from files instead
# move to https meanwhile
# add authentication
# deliver the public key as part of the filesystem
# On the receiving end
# echo "$GPG_PUB" | apt-key add
# apt-get -o Dir::Etc::SourceList=/dev/stdin update

# XXX to remove: aptly -config /config/aptly/main.conf publish drop buster-updates :archive/debian/$LONG_DATE
