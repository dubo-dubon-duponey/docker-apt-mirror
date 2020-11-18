# Docker Aptly

```bash

# Start the way you want
docker run -d \
    --cap-drop ALL \
    --read-only \
    dubodubonduponey/aptly

# Trust Debian keys
docker exec -ti apt-mirror /boot/entrypoint.sh trust keys.gnupg.net 04EE7237B7D453EC 648ACFD622F3D138 EF0F382A1A7B6500 DCC9EFBF77E11517 AA8E81B4331F7F50 112695A0E562B32A

# Generate your signing key
docker exec -ti apt-mirror /boot/entrypoint.sh init "Dubo Dubon Duponey" dubodubonduponey@jsboot.space

# Create new mirrors
docker exec -ti apt-mirror /boot/entrypoint.sh create buster-main-mirror http://deb.debian.org/debian buster main
docker exec -ti apt-mirror /boot/entrypoint.sh create buster-updates-main-mirror http://deb.debian.org/debian buster-updates main
docker exec -ti apt-mirror /boot/entrypoint.sh create buster-security-main-mirror http://security.debian.org/debian-security buster/updates main

# Force a first refresh of all mirrors
docker exec -ti apt-mirror /boot/entrypoint.sh refresh
```

