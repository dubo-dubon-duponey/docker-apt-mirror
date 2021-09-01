# Docker Apt Mirror

```bash

# Start the way you want
docker run -d \
    --name apt-mirror \
    --cap-drop ALL \
    --read-only \
    ghcr.io/dubo-dubon-duponey/apt-mirror

# Trust whichever keys you want to trust
# Debian 9
docker exec -ti apt-mirror /boot/entrypoint.sh trust hkps://keyserver.ubuntu.com EF0F382A1A7B6500 04EE7237B7D453EC AA8E81B4331F7F50
# Debian 10
docker exec -ti apt-mirror /boot/entrypoint.sh trust hkps://keyserver.ubuntu.com DCC9EFBF77E11517 648ACFD622F3D138 112695A0E562B32A
# Debian 11
docker exec -ti apt-mirror /boot/entrypoint.sh trust hkps://keyserver.ubuntu.com 0E98404D386FA1D9 54404762BBB6E853 605C66F00D6C9793

# Generate your signing key
docker exec -ti apt-mirror /boot/entrypoint.sh init "Dubo Dubon Duponey" dubodubonduponey@jsboot.space

# Create new mirrors
docker exec -ti apt-mirror /boot/entrypoint.sh create buster-main-mirror http://deb.debian.org/debian buster main
docker exec -ti apt-mirror /boot/entrypoint.sh create buster-updates-main-mirror http://deb.debian.org/debian buster-updates main
docker exec -ti apt-mirror /boot/entrypoint.sh create buster-security-main-mirror http://security.debian.org/debian-security buster/updates main

# Force a first refresh of all mirrors
docker exec -ti apt-mirror /boot/entrypoint.sh refresh
```

