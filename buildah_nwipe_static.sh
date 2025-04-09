#!/bin/bash
set -e

# Create output directory
mkdir -p out
# Set default architecture to amd64 if not provided
ARCH=${ARCH:-amd64}

NWIPE_VERSION=${NWIPE_VERSION:-0.38}
PARTED_VERSION=${PARTED_VERSION:-3.6}

# Create the build container
export ctr=$(buildah from --arch $ARCH quay.io/deamen/alpine-base:latest)
buildah config --label maintainer="Song Tang" $ctr

# Install base build tools and dependencies
buildah run $ctr -- apk add --no-cache \
  gettext gperf texinfo rsync libuuid util-linux-dev device-mapper-libs \
  lvm2-dev readline-dev device-mapper-static util-linux-static lvm2-static \
  readline-static ncurses-static gcc build-base wget parted-dev \
  libconfig-dev automake autoconf make ncurses-dev linux-headers \
  ncurses-libs ncurses-static libconfig-static gnupg

# Set working directory
buildah run $ctr -- mkdir -p /build
buildah config --workingdir /build $ctr

# Download
buildah run $ctr -- wget -c https://mirror.ossplanet.net/gnu/parted/parted-$PARTED_VERSION.tar.xz

# Verify gpg signature
buildah run $ctr -- wget -c https://mirror.ossplanet.net/gnu/parted/parted-$PARTED_VERSION.tar.xz.sig
buildah run $ctr -- sh -c "wget -q -O- 'https://savannah.gnu.org/project/release-gpgkeys.php?group=parted&download=1' | gpg --import -"
buildah run $ctr -- gpg --verify parted-3.6.tar.xz.sig parted-3.6.tar.xz

# Build static parted
buildah run $ctr -- tar -xf parted-$PARTED_VERSION.tar.xz
buildah run $ctr -- sh -c "cd parted-$PARTED_VERSION && ./configure --enable-static && make -j$(nproc --ignore 1) && make install"

# Download and build static nwipe
buildah run $ctr -- wget -c https://github.com/martijnvanbrummelen/nwipe/archive/refs/tags/v$NWIPE_VERSION.tar.gz
buildah run $ctr -- tar -zxf v$NWIPE_VERSION.tar.gz

# Apply patch for static build
buildah copy $ctr ./0001-Conditionally-check-static-libraries.patch .
buildah copy $ctr ./0002-Remove-libintl-from-static-linking-library.patch .
buildah run $ctr -- sh -c "cd nwipe-$NWIPE_VERSION && patch -p1 < ../0001-Conditionally-check-static-libraries.patch"
buildah run $ctr -- sh -c "cd nwipe-$NWIPE_VERSION && patch -p1 < ../0002-Remove-libintl-from-static-linking-library.patch"

# Bild static nwipe
buildah run $ctr -- sh -c "cd nwipe-$NWIPE_VERSION && sh autogen.sh && ./configure LDFLAGS=-static && make -j$(nproc --ignore 1)"
buildah run $ctr -- strip nwipe-$NWIPE_VERSION/src/nwipe

copy_script="copy_artifacts.sh"
cat << 'EOF' >> $copy_script
#!/bin/sh
mnt=$(buildah mount $ctr)
cp $mnt/$1 ./out/$2
buildah umount $ctr
EOF
chmod a+x $copy_script
buildah unshare ./$copy_script /build/nwipe-$NWIPE_VERSION/src/nwipe nwipe
rm ./$copy_script
buildah rm $ctr
