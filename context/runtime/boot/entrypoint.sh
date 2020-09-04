#!/usr/bin/env bash
set -o errexit -o errtrace -o functrace -o nounset -o pipefail

# Ensure the data folder is writable
[ -w "/data" ] || {
  printf >&2 "/data is not writable. Check your mount permissions.\n"
  exit 1
}

# System constants
readonly PORT="${PORT:-}"
readonly ARCHITECTURES="${ARCHITECTURES:-}"

readonly CONFIG_LOCATION="${CONFIG_LOCATION:-/config/aptly.conf}"
readonly GPG_HOME="/data/gpg"
readonly KEYRING_LOCATION="${KEYRING_LOCATION:-$GPG_HOME/trustedkeys.gpg}"

readonly SUITE=buster
readonly DATE="$(date +%Y-%m-%d)"
readonly LONG_DATE="$(date +%Y%m%dT000000Z)"

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
  >&2 printf "You need to apt-key add %s to consume this repo\n" "$GPG_HOME/snapshot-signing-public-key.pgp"
}

aptly::refresh(){
  local mirros
  local mir
  mirros="$(aptly -config="$CONFIG_LOCATION" -architectures="$ARCHITECTURES" mirror list -raw)"
  while true; do
    for mir in $mirros; do
      >&2 printf "Updating existing mirror %s\n" "$mir"
      aptly -keyring="$KEYRING_LOCATION" -config="$CONFIG_LOCATION" -architectures="$ARCHITECTURES" mirror update "$mir"

      # If we have a published snapshot at that date already, just continue
      >&2 printf "Have a published one already? If yes, continue.\n"
      ! aptly -config="$CONFIG_LOCATION" -architectures="$ARCHITECTURES" publish show "$mir" :"archive/$mir/$LONG_DATE" > /dev/null || continue

      # If we don't have a snapshot, create one
      if ! aptly -config="$CONFIG_LOCATION" -architectures="$ARCHITECTURES" snapshot show "$mir-$DATE" > /dev/null; then
        >&2 printf "No snapshot yet for that date and mirror, create one.\n"
        aptly -config="$CONFIG_LOCATION" -architectures="$ARCHITECTURES" snapshot create "$mir-$DATE" from mirror "$mir" > /dev/null
      fi

      # And publish
      >&2 printf "And... publish it\n"
      aptly -keyring="$KEYRING_LOCATION" -config="$CONFIG_LOCATION" -architectures="$ARCHITECTURES" publish snapshot "$mir-$DATE" :"archive/$mir/$LONG_DATE" # > /dev/null
    done
    >&2 printf "Going to sleep for a day now\n"
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
"refresh")
  aptly::refresh
  exit
  ;;
*)
  #aptly::refresh &

  # Bonjour the container
  if [ "${MDNS_NAME:-}" ]; then
    goello-server -name "$MDNS_NAME" -host "$MDNS_HOST" -port "$PORT" -type "$MDNS_TYPE" &
  fi
  # Start our little caddy
  exec caddy run -config /config/caddy/main.conf --adapter caddyfile "$@"
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
# gpg --no-default-keyring --keyring /data/gpg/trustedkeys.gpg --list-keys

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
