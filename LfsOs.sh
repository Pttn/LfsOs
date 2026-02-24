#!/bin/bash

# (c) 2026-present Pttn
# Distributed under the Gpl3 License, see https://www.gnu.org/licenses/gpl-3.0.en.html

# LfsOs: Linux From Scratch, OverSimplified
# Shell Script that will build a whole (simplified) Linux System based on the Linux From Scratch Book: https://linuxfromscratch.org/.
# GitHub: https://github.com/Pttn/LfsOs

# To be run as Root!

# Abort Script on Error (in this case, clean up with the "CleanUp" Argument like "bash LfsOs.sh CleanUp").
set -e

# Choose the Name of the final OS Disk Image, which can then be used as Disk Image for Qemu or directly copied to some Drive to Boot on an actual Uefi Machine.
export IMG=$PWD/LfsOs.img
# Choose a Loop Device, change if it "failed to set up loop device: Device or resource busy"
# Use "losetup -f" to get an available Loop Device.
export LOOP=/dev/loop1
# Lfs 2.6: choose the Mount Point for the Build, can simply be any Empty Directory (created if not Existing).
# Also set UMask as recommended by the Book.
export LFS=/mnt/LfsOs
umask 022

# Put Packages Sources in this Directory.
export LFSPACKAGES=$PWD/LfsOsPackages

# Temporary Username for Lfs 5-6.
export LFSUSER=Lfs
export LFSGROUP=$LFSUSER

# Get First Argument of the Script. Then the Script will directly jump to the appropriate If or Elif Section.
# For now only nothing, "DownloadPackages" and "CleanUp" are really useful for the User, some other values are internally used to go to the next step.
export STEP=$1

if [[ $STEP = "" ]]; then
# Create Mount Point, Check If Empty if Already Exists.
mkdir -pv $LFS
if [ ! -z "$(ls -A $LFS)" ]; then
	echo "$LFS must be Empty!"
	exit
fi

if [ ! -d $LFSPACKAGES ]; then
	echo "$LFSPACKAGES Missing or Not a Directory!"
	echo "Run 'bash $0 DownloadPackages' to download the Packages (or get them manually)!"
	exit
elif [ -z "$(ls -A $LFSPACKAGES)" ]; then
	echo "$LFSPACKAGES Empty!"
	echo "Run 'bash $0 DownloadPackages' to download the Packages (or get them manually)!"
	exit
fi

# Create 10 GiB Image.
dd if=/dev/zero of=$IMG bs=1G count=10 status=progress

# Create Gpt Disk Layout with Efi Fat32 Partition and Ext4 Root Partition.
parted -s $IMG --                   \
	mklabel gpt                     \
	mkpart primary fat32 1MiB 65MiB \
	set 1 esp on                    \
	mkpart primary ext4 65MiB 100%

# Lfs 2.5: Create File Systems (using Loop Devices to not bother with an actual Drive).
losetup -P $LOOP $IMG
mkfs.fat -F32 -v ${LOOP}p1
mkfs -v -t ext4 ${LOOP}p2

# Lfs 2.7: Mount Root Partition.
mount -v -t ext4 ${LOOP}p2 $LFS

# Lfs 4.2: Create Limited Directory Layout, copy Package Sources.
mkdir -pv $LFS/tools
cp -rv $LFSPACKAGES $LFS/sources
mkdir -pv $LFS/{etc,var} $LFS/usr/{bin,lib,sbin}
for i in bin lib sbin; do
	ln -sv usr/$i $LFS/$i
done
case $(uname -m) in
	x86_64) mkdir -pv $LFS/lib64 ;;
esac

# Lfs 4.3: Create Temporary User to limit risks while building the initial programs.
groupadd $LFSGROUP
useradd -s /bin/bash -g $LFSGROUP -m -k /dev/null $LFSUSER

# Make that User temporary own the Directories.
chown -v $LFSUSER $LFS/{usr{,/*},var,etc,sources,tools}
case $(uname -m) in
	x86_64) chown -v $LFSUSER $LFS/lib64 ;;
esac

# Login as Temporary User with empty Environment, which is setup later.
# Start the first part of Building Lfs (Sections 4.4 to last 6.x) by rerunning this Script ($0 expands to its Name) under a Subshell with the Step as Argument. The Subshell starts at the Elif Build1 position. Doing just "su - $LFSUSER" like in the Lfs Book will not work in a Script.
su $LFSUSER -c "env -i bash $0 Build1"

# Once Build1 is done, the Subshell ends and the execution resumes here in the original Shell.

# Lfs 7.2: Revert Owner to Root.
chown --from $LFSUSER -R root:root $LFS/{usr,var,etc,tools}
case $(uname -m) in
  x86_64) chown --from $LFSUSER -R root:root $LFS/lib64 ;;
esac

# The Temporary User is no longer needed.
userdel -r $LFSUSER

# Lfs 7.3: Mount Virtual Kernel File Systems.
mkdir -pv $LFS/{dev,proc,sys,run}
mount -v --bind /dev $LFS/dev
mount -vt devpts devpts -o gid=5,mode=0620 $LFS/dev/pts
mount -vt proc proc $LFS/proc
mount -vt sysfs sysfs $LFS/sys
mount -vt tmpfs tmpfs $LFS/run
mount -vt tmpfs -o nosuid,nodev tmpfs $LFS/dev/shm

# Copy the Script to make it accessible in the Chroot.
cp -v $0 $LFS/$0
# Lfs 7.4: Entering the Chroot Environment.
# Like for Building with the Lfs User, Chrooting needs a Subshell. We rerun the (copied) Script starting at the Elif Build2.
chroot $LFS /usr/bin/env -i HOME=/root TERM="$$TERM" PS1='LfsOs \u:\w\$$ ' PATH=/usr/bin:/usr/sbin MAKEFLAGS="-j$(nproc)" TESTSUITEFLAGS="-j$(nproc)" /bin/bash --login $0 Build2

# Redo Chroot after installing the final Bash (just doing the Book's "exec /usr/bin/bash --login" will not work), finish the remaining Builds.
chroot $LFS /usr/bin/env -i HOME=/root TERM="$$TERM" PS1='LfsOs \u:\w\$$ ' PATH=/usr/bin:/usr/sbin MAKEFLAGS="-j$(nproc)" TESTSUITEFLAGS="-j$(nproc)" /bin/bash --login $0 Build3

# Unmount Virtual Kernel File Systems. Run this manually if Script aborted Early.
bash $0 CleanUp


elif [[ $STEP = "DownloadPackages" ]]; then

if [ ! -z "$(ls -A $LFSPACKAGES)" ]; then
	echo "$LFSPACKAGES Not a Dir or Not Empty, Packages might already have been Downloaded!"
	exit
fi

mkdir -pv $LFSPACKAGES

cd $LFSPACKAGES

# Lfs 3: Download Packages.
wget https://download.savannah.gnu.org/releases/acl/acl-2.3.2.tar.xz
wget https://download.savannah.gnu.org/releases/attr/attr-2.5.2.tar.gz
wget https://ftpmirror.gnu.org/autoconf/autoconf-2.72.tar.xz
wget https://ftpmirror.gnu.org/automake/automake-1.18.1.tar.xz
wget https://ftpmirror.gnu.org/bash/bash-5.3.tar.gz
wget https://github.com/gavinhoward/bc/releases/download/7.0.3/bc-7.0.3.tar.xz
wget https://sourceware.org/pub/binutils/releases/binutils-2.46.0.tar.xz
wget https://ftpmirror.gnu.org/bison/bison-3.8.2.tar.xz
wget https://www.sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz
wget https://ftpmirror.gnu.org/coreutils/coreutils-9.10.tar.xz
wget https://ftpmirror.gnu.org/dejagnu/dejagnu-1.6.3.tar.gz
wget https://ftpmirror.gnu.org/diffutils/diffutils-3.12.tar.xz
wget https://downloads.sourceforge.net/project/e2fsprogs/e2fsprogs/v1.47.3/e2fsprogs-1.47.3.tar.gz
wget https://github.com/rhboot/efibootmgr/archive/18/efibootmgr-18.tar.gz
wget https://github.com/rhboot/efivar/archive/39/efivar-39.tar.gz
wget https://github.com/libexpat/libexpat/releases/download/R_2_7_4/expat-2.7.4.tar.xz
wget https://prdownloads.sourceforge.net/expect/expect5.45.4.tar.gz
wget https://www.linuxfromscratch.org/patches/lfs/development/expect-5.45.4-gcc15-1.patch
wget https://astron.com/pub/file/file-5.46.tar.gz
wget https://ftpmirror.gnu.org/findutils/findutils-4.10.0.tar.xz
wget https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz
wget https://pypi.org/packages/source/f/flit-core/flit_core-3.12.0.tar.gz
wget https://ftpmirror.gnu.org/gawk/gawk-5.3.2.tar.xz
wget https://ftpmirror.gnu.org/gcc/gcc-15.2.0/gcc-15.2.0.tar.xz
wget https://ftpmirror.gnu.org/gdbm/gdbm-1.26.tar.gz
wget https://ftpmirror.gnu.org/gmp/gmp-6.3.0.tar.xz
wget https://ftpmirror.gnu.org/gperf/gperf-3.3.tar.gz
wget https://ftpmirror.gnu.org/grep/grep-3.12.tar.xz
wget https://ftpmirror.gnu.org/grub/grub-2.14.tar.xz
wget https://ftpmirror.gnu.org/gzip/gzip-1.14.tar.xz
wget https://pypi.org/packages/source/J/Jinja2/jinja2-3.1.6.tar.gz
wget https://www.kernel.org/pub/linux/utils/kbd/kbd-2.9.0.tar.xz
wget https://www.kernel.org/pub/linux/utils/kernel/kmod/kmod-34.2.tar.xz
wget https://www.greenwoodsoftware.com/less/less-692.tar.gz
wget https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-2.77.tar.xz
wget https://github.com/arachsys/libelf/archive/refs/tags/v0.193.tar.gz -O libelf-0.193.tar.gz
wget https://github.com/libffi/libffi/releases/download/v3.5.2/libffi-3.5.2.tar.gz
wget https://ftpmirror.gnu.org/libtool/libtool-2.5.4.tar.xz
wget https://github.com/besser82/libxcrypt/releases/download/v4.5.2/libxcrypt-4.5.2.tar.xz
wget https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.18.10.tar.xz
wget https://github.com/lz4/lz4/releases/download/v1.10.0/lz4-1.10.0.tar.gz
wget https://ftpmirror.gnu.org/m4/m4-1.4.21.tar.xz
wget https://ftpmirror.gnu.org/make/make-4.4.1.tar.gz
wget https://pypi.org/packages/source/M/MarkupSafe/markupsafe-3.0.3.tar.gz
wget https://github.com/mesonbuild/meson/releases/download/1.10.1/meson-1.10.1.tar.gz
wget https://ftpmirror.gnu.org/mpc/mpc-1.3.1.tar.gz
wget https://ftpmirror.gnu.org/mpfr/mpfr-4.2.2.tar.xz
wget https://musl.libc.org/releases/musl-1.2.5.tar.gz
wget https://www.nano-editor.org/dist/v8/nano-8.7.1.tar.xz
wget https://invisible-mirror.net/archives/ncurses/ncurses-6.6.tar.gz
wget https://github.com/ninja-build/ninja/archive/v1.13.2/ninja-1.13.2.tar.gz
wget https://github.com/openssl/openssl/releases/download/openssl-3.6.1/openssl-3.6.1.tar.gz
wget https://files.pythonhosted.org/packages/source/p/packaging/packaging-26.0.tar.gz
wget https://ftpmirror.gnu.org/patch/patch-2.8.tar.xz
wget https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.47/pcre2-10.47.tar.bz2
wget https://www.cpan.org/src/5.0/perl-5.42.0.tar.xz
wget https://distfiles.ariadne.space/pkgconf/pkgconf-2.5.1.tar.xz
wget https://ftp.osuosl.org/pub/rpm/popt/releases/popt-1.x/popt-1.19.tar.gz
wget https://sourceforge.net/projects/procps-ng/files/Production/procps-ng-4.0.6.tar.xz
wget https://sourceforge.net/projects/psmisc/files/psmisc/psmisc-23.7.tar.xz
wget https://www.python.org/ftp/python/3.14.3/Python-3.14.3.tar.xz
wget https://ftpmirror.gnu.org/readline/readline-8.3.tar.gz
wget https://ftpmirror.gnu.org/sed/sed-4.9.tar.xz
wget https://pypi.org/packages/source/s/setuptools/setuptools-82.0.0.tar.gz
wget https://github.com/shadow-maint/shadow/releases/download/4.19.3/shadow-4.19.3.tar.xz
wget https://sqlite.org/2026/sqlite-autoconf-3510200.tar.gz
wget https://github.com/systemd/systemd/archive/v259.1/systemd-259.1.tar.gz
wget https://ftpmirror.gnu.org/tar/tar-1.35.tar.xz
wget https://downloads.sourceforge.net/tcl/tcl8.6.17-src.tar.gz
wget https://www.kernel.org/pub/linux/utils/util-linux/v2.41/util-linux-2.41.3.tar.xz
wget https://pypi.org/packages/source/w/wheel/wheel-0.46.3.tar.gz
wget https://cpan.metacpan.org/authors/id/T/TO/TODDR/XML-Parser-2.47.tar.gz
wget https://github.com//tukaani-project/xz/releases/download/v5.8.2/xz-5.8.2.tar.xz
wget https://zlib.net/fossils/zlib-1.3.2.tar.gz
wget https://github.com/facebook/zstd/releases/download/v1.5.7/zstd-1.5.7.tar.gz

elif [[ $STEP = "Build1" ]]; then
# Lfs 4.4: Setup the Environment (directly Export without using BashRc File and Source).
set +h
export LC_ALL=C
export LFS_TGT=$(uname -m)-lfs-linux-musl
PATH=/usr/bin
if [ ! -L /bin ]; then PATH=/bin:$PATH; fi
export PATH=$LFS/tools/bin:$PATH
export CONFIG_SITE=$LFS/usr/share/config.site
export MAKEFLAGS=-j$(nproc)

cd $LFS/sources/

# Lfs 5: Build Cross Toolchain.

# Builds will often follow this structure, detailled once for this first Package.
# Decompress Source and Enter to newly created Source Directory.
tar -xf binutils-2.46.0.tar.xz
cd binutils-2.46.0
# Sometimes recommended to create dedicated Build Dir.
mkdir Build
cd Build
# Compilation Steps. Read the Lfs Section about a given Package to learn more, or consult the Software's Documentation.
../configure --prefix=$LFS/tools --with-sysroot=$LFS --target=$LFS_TGT --disable-nls --enable-gprofng=no --disable-werror --enable-new-dtags --enable-default-hash-style=gnu
make
# Install to System.
make install
# Cleaning Up.
cd ..
rm -rfv Build
cd ..

tar -xf gcc-15.2.0.tar.xz
cd gcc-15.2.0
tar -xf ../mpfr-4.2.2.tar.xz
mv -v mpfr-4.2.2 mpfr
tar -xf ../gmp-6.3.0.tar.xz
mv -v gmp-6.3.0 gmp
tar -xf ../mpc-1.3.1.tar.gz
mv -v mpc-1.3.1 mpc
case $(uname -m) in
  x86_64) sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64 ;;
esac
mkdir Build
cd Build
../configure --target=$LFS_TGT --prefix=$LFS/tools --with-sysroot=$LFS --with-newlib --without-headers --enable-default-pie --enable-default-ssp --disable-nls --disable-shared --disable-multilib --disable-threads --disable-libatomic --disable-libgomp --disable-libquadmath --disable-libssp --disable-libvtv --disable-libstdcxx --enable-languages=c,c++
make 
make install
cd ..
rm -rfv Build
cd ..

tar -xf linux-6.18.10.tar.xz
cd linux-6.18.10
make mrproper
make headers
find usr/include -type f ! -name '*.h' -delete
cp -rv usr/include $LFS/usr
cd ..
rm -rfv linux-6.18.10

tar -xf musl-1.2.5.tar.gz
cd musl-1.2.5
./configure --prefix=/usr --host=$LFS_TGT --build=$(../scripts/config.guess) libc_cv_slibdir=/usr/lib
make
make DESTDIR=$LFS install
cd ..
rm -rfv musl-1.2.5

cd gcc-15.2.0
mkdir Build
cd Build
../libstdc++-v3/configure --host=$LFS_TGT --build=$(../config.guess) --prefix=/usr --disable-multilib --disable-nls --disable-libstdcxx-pch --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/15.2.0
make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la
cd ..
rm -rfv Build
cd ..

# Lfs 6: Cross Compiling Temporary Tools.

tar -xf m4-1.4.21.tar.xz
cd m4-1.4.21
./configure --prefix=/usr --host=$LFS_TGT --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cd ..
rm -rfv m4-1.4.21

tar -xf ncurses-6.6.tar.gz
cd ncurses-6.6
mkdir build
pushd build
  ../configure --prefix=$LFS/tools AWK=gawk
  make -C include
  make -C progs tic
  install progs/tic $LFS/tools/bin
popd
./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess) --with-shared --without-normal --with-cxx-shared --without-debug --without-ada --disable-stripping AWK=gawk
make
make DESTDIR=$LFS install
ln -sv libncursesw.so $LFS/usr/lib/libncurses.so
sed -e 's/^#if.*XOPEN.*$/#if 1/' -i $LFS/usr/include/curses.h
cd ..
rm -rfv ncurses-6.6

tar -xf bash-5.3.tar.gz
cd bash-5.3
./configure --prefix=/usr --build=$(sh support/config.guess) --host=$LFS_TGT --without-bash-malloc
make
make DESTDIR=$LFS install
ln -sv bash $LFS/bin/sh
cd ..
rm -rfv bash-5.3

tar -xf coreutils-9.10.tar.xz
cd coreutils-9.10
./configure --prefix=/usr --host=$LFS_TGT --build=$(build-aux/config.guess) --enable-install-program=hostname --enable-no-install-program=kill,uptime
make
make DESTDIR=$LFS install
cd ..
rm -rfv coreutils-9.10

tar -xf diffutils-3.12.tar.xz
cd diffutils-3.12
./configure --prefix=/usr --host=$LFS_TGT gl_cv_func_strcasecmp_works=y --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install
cd ..
rm -rfv diffutils-3.12

tar -xf file-5.46.tar.gz
cd file-5.46
mkdir build
pushd build
  ../configure --disable-bzlib --disable-libseccomp --disable-xzlib --disable-zlib
  make
popd
./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
make FILE_COMPILE=$(pwd)/build/src/file
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/libmagic.la
cd ..
rm -rfv file-5.46

tar -xf findutils-4.10.0.tar.xz
cd findutils-4.10.0
./configure --prefix=/usr --localstatedir=/var/lib/locate --host=$LFS_TGT --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cd ..
rm -rfv findutils-4.10.0

tar -xf gawk-5.3.2.tar.xz
cd gawk-5.3.2
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr --host=$LFS_TGT --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cd ..
rm -rfv gawk-5.3.2

tar -xf grep-3.12.tar.xz
cd grep-3.12
./configure --prefix=/usr --host=$LFS_TGT --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install
cd ..
rm -rfv grep-3.12

tar -xf gzip-1.14.tar.xz
cd gzip-1.14
./configure --prefix=/usr --host=$LFS_TGT
make
make DESTDIR=$LFS install
cd ..
rm -rfv gzip-1.14

tar -xf make-4.4.1.tar.gz
cd make-4.4.1
# Fixes for Musl.
sed -i -e 's/getenv ();/getenv (const char *);/g' lib/fnmatch.c
sed -i -e 's/getenv ();/getenv (const char *);/g' src/getopt.c
sed -i -e 's/getopt ();/getopt (int,  char * const*, const char *);/g' src/getopt.h
./configure --prefix=/usr --host=$LFS_TGT --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cd ..
rm -rfv make-4.4.1

tar -xf sed-4.9.tar.xz
cd sed-4.9
./configure --prefix=/usr --host=$LFS_TGT --build=$(./build-aux/config.guess)
make
make DESTDIR=$LFS install
cd ..
rm -rfv sed-4.9

tar -xf tar-1.35.tar.xz
cd tar-1.35
./configure --prefix=/usr --host=$LFS_TGT --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
cd ..
rm -rfv tar-1.35

tar -xf xz-5.8.2.tar.xz
cd xz-5.8.2
./configure --prefix=/usr --host=$LFS_TGT --build=$(build-aux/config.guess)
make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/liblzma.la
cd ..
rm -rfv xz-5.8.2

cd binutils-2.46.0
sed '6031s/$add_dir//' -i ltmain.sh
mkdir Build
cd Build
../configure --prefix=/usr --build=$(../config.guess) --host=$LFS_TGT --disable-nls --enable-gprofng=no --disable-werror --enable-64-bit-bfd --enable-new-dtags --enable-default-hash-style=gnu
make
make DESTDIR=$LFS install
rm -v $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.la

cd ..
rm -rfv Build
cd ..

cd gcc-15.2.0
sed '/thread_header =/s/@.*@/gthr-posix.h/' -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in
mkdir Build
cd Build
../configure --build=$(../config.guess) --host=$LFS_TGT --target=$LFS_TGT --prefix=/usr --with-build-sysroot=$LFS --enable-default-pie --enable-default-ssp --disable-nls --disable-multilib --disable-libatomic --disable-libgomp --disable-libquadmath --disable-libsanitizer --disable-libssp --disable-libvtv --enable-languages=c,c++ LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc
make
make DESTDIR=$LFS install
ln -sv gcc $LFS/usr/bin/cc
cd ..
rm -rfv Build


elif [[ $STEP = "Build2" ]]; then
# Lfs 7.5: Create Remaining Directories.
mkdir -pv /{boot,home,mnt,opt,srv}
mkdir -pv /etc/{opt,sysconfig}
mkdir -pv /lib/firmware
mkdir -pv /media/{floppy,cdrom}
mkdir -pv /usr/{,local/}{include,src}
mkdir -pv /usr/lib/locale
mkdir -pv /usr/local/{bin,lib,sbin}
mkdir -pv /usr/{,local/}share/{color,dict,doc,info,locale,man}
mkdir -pv /usr/{,local/}share/{misc,terminfo,zoneinfo}
mkdir -pv /usr/{,local/}share/man/man{1..8}
mkdir -pv /var/{cache,local,log,mail,opt,spool}
mkdir -pv /var/lib/{color,misc,locate}

ln -sfv /run /var/run
ln -sfv /run/lock /var/lock

install -dv -m 0750 /root
install -dv -m 1777 /tmp /var/tmp

# Lfs 7.6: Create Essential Files and Symlinks.

cat > /etc/hosts << EOF
127.0.0.1  localhost $(hostname)
::1        localhost
EOF

cat > /etc/passwd << "EOF"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
systemd-journal-gateway:x:73:73:systemd Journal Gateway:/:/usr/bin/false
systemd-journal-remote:x:74:74:systemd Journal Remote:/:/usr/bin/false
systemd-journal-upload:x:75:75:systemd Journal Upload:/:/usr/bin/false
systemd-network:x:76:76:systemd Network Management:/:/usr/bin/false
systemd-resolve:x:77:77:systemd Resolver:/:/usr/bin/false
systemd-timesync:x:78:78:systemd Time Synchronization:/:/usr/bin/false
systemd-coredump:x:79:79:systemd Core Dumper:/:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
systemd-oom:x:81:81:systemd Out Of Memory Daemon:/:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
EOF

cat > /etc/group << "EOF"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
clock:x:14:
cdrom:x:15:
adm:x:16:
systemd-journal:x:23:
input:x:24:
mail:x:34:
kvm:x:61:
systemd-journal-gateway:x:73:
systemd-journal-remote:x:74:
systemd-journal-upload:x:75:
systemd-network:x:76:
systemd-resolve:x:77:
systemd-timesync:x:78:
systemd-coredump:x:79:
uuidd:x:80:
systemd-oom:x:81:
wheel:x:97:
users:x:999:
nogroup:x:65534:
EOF

# Uncomment to run some Tests requiring a Dummy User
# echo "tester:x:101:101::/home/tester:/bin/bash" >> /etc/passwd
# echo "tester:x:101:" >> /etc/group
# install -o tester -d /home/tester

touch /var/log/{btmp,lastlog,faillog,wtmp}
chgrp -v utmp /var/log/lastlog
chmod -v 664  /var/log/lastlog
chmod -v 600  /var/log/btmp

# Lfs 7.7-7.12: Build Remaining Temporary Tools.

cd /sources

tar -xf bison-3.8.2.tar.xz
cd bison-3.8.2
./configure --prefix=/usr
make
make install
cd ..
rm -rfv bison-3.8.2

tar -xf perl-5.42.0.tar.xz
cd perl-5.42.0
# Musl needs that AccFlag.
sh Configure -des -D prefix=/usr -D vendorprefix=/usr -D privlib=/usr/lib/perl5/5.42/core_perl -D archlib=/usr/lib/perl5/5.42/core_perl -D sitelib=/usr/lib/perl5/5.42/site_perl -D sitearch=/usr/lib/perl5/5.42/site_perl -D vendorlib=/usr/lib/perl5/5.42/vendor_perl -D vendorarch=/usr/lib/perl5/5.42/vendor_perl -Accflags="-D_GNU_SOURCE"
make
make install
cd ..
rm -rfv perl-5.42.0

tar -xf Python-3.14.3.tar.xz
cd Python-3.14.3
./configure --prefix=/usr --without-ensurepip --without-static-libpython
make
make install
cd ..
rm -rfv Python-3.14.3

tar -xf util-linux-2.41.3.tar.xz
cd util-linux-2.41.3
mkdir -pv /var/lib/hwclock
./configure --libdir=/usr/lib --runstatedir=/run --disable-chfn-chsh --disable-login --disable-nologin --disable-su --disable-setpriv --disable-runuser --disable-pylibmount --disable-liblastlog2 --without-python ADJTIME_PATH=/var/lib/hwclock/adjtime
make
make install
cd ..
rm -rfv util-linux-2.41.3

# Lfs 7.13: Clean Up

rm -rfv /usr/share/{info,man,doc}/*
find /usr/{lib,libexec} -name \*.la -delete
rm -rfv /tools

# Lfs 8: Build and Instal Basic System Software.

tar -xf musl-1.2.5.tar.gz
cd musl-1.2.5
./configure --prefix=/usr --disable-nscd libc_cv_slibdir=/usr/lib --enable-stack-protector=strong
make
make install
cd ..
rm -rfv musl-1.2.5

tar -xf zlib-1.3.2.tar.gz
cd zlib-1.3.2
./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv zlib-1.3.2

tar -xf bzip2-1.0.8.tar.gz
cd bzip2-1.0.8
sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
make -f Makefile-libbz2_so
make clean
make
make PREFIX=/usr install
cp -av libbz2.so.* /usr/lib
ln -sfv libbz2.so.1.0.8 /usr/lib/libbz2.so
ln -sv libbz2.so.1.0.8 /usr/lib/libbz2.so.1
cp -v bzip2-shared /usr/bin/bzip2
for i in /usr/bin/{bzcat,bunzip2}; do
	ln -sfv bzip2 $i
done
cd ..
rm -rfv bzip2-1.0.8

tar -xf xz-5.8.2.tar.xz
cd xz-5.8.2
./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv xz-5.8.2

tar -xf lz4-1.10.0.tar.gz
cd lz4-1.10.0
make PREFIX=/usr
# make -j1 check
make PREFIX=/usr install
cd ..
rm -rfv lz4-1.10.0

tar -xf zstd-1.5.7.tar.gz
cd zstd-1.5.7
make prefix=/usr
# make check
make prefix=/usr install
cd ..
rm -rfv zstd-1.5.7

tar -xf file-5.46.tar.gz
cd file-5.46
./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv file-5.46

tar -xf readline-8.3.tar.gz
cd readline-8.3
sed -i '/MV.*old/d' Makefile.in
sed -i '/{OLDSUFF}/c:' support/shlib-install
sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
sed -e '270a\
     else\
       chars_avail = 1;'      \
    -e '288i\   result = -1;' \
    -i.orig input.c
./configure --prefix=/usr --with-curses
make SHLIB_LIBS="-lncursesw"
make install
cd ..
rm -rfv readline-8.3

tar -xf pcre2-10.47.tar.bz2
cd pcre2-10.47
./configure --prefix=/usr --enable-unicode --enable-jit --enable-pcre2-16 --enable-pcre2-32 --enable-pcre2grep-libz --enable-pcre2grep-libbz2 --enable-pcre2test-libreadline
make
# make check
make install
cd ..
rm -rfv pcre2-10.47

tar -xf m4-1.4.21.tar.xz
cd m4-1.4.21
./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv m4-1.4.21

tar -xf bc-7.0.3.tar.xz
cd bc-7.0.3
CC='gcc -std=c99' ./configure --prefix=/usr -G -O3 -r
make
# make test
make install
cd ..
rm -rfv bc-7.0.3

tar -xf flex-2.6.4.tar.gz
cd flex-2.6.4
./configure --prefix=/usr
make
# make check
make install
ln -sv flex /usr/bin/lex
ln -sv flex.1 /usr/share/man/man1/lex.1
cd ..
rm -rfv flex-2.6.4

tar -xf tcl8.6.17-src.tar.gz
cd tcl8.6.17
SRCDIR=$(pwd)
cd unix
./configure --prefix=/usr --disable-rpath
make
sed -e "s|$SRCDIR/unix|/usr/lib|" \
    -e "s|$SRCDIR|/usr/include|"  \
    -i tclConfig.sh
sed -e "s|$SRCDIR/unix/pkgs/tdbc1.1.12|/usr/lib/tdbc1.1.12|" \
    -e "s|$SRCDIR/pkgs/tdbc1.1.12/generic|/usr/include|"     \
    -e "s|$SRCDIR/pkgs/tdbc1.1.12/library|/usr/lib/tcl8.6|"  \
    -e "s|$SRCDIR/pkgs/tdbc1.1.12|/usr/include|"             \
    -i pkgs/tdbc1.1.12/tdbcConfig.sh
sed -e "s|$SRCDIR/unix/pkgs/itcl4.3.4|/usr/lib/itcl4.3.4|" \
    -e "s|$SRCDIR/pkgs/itcl4.3.4/generic|/usr/include|"    \
    -e "s|$SRCDIR/pkgs/itcl4.3.4|/usr/include|"            \
    -i pkgs/itcl4.3.4/itclConfig.sh
unset SRCDIR
#LC_ALL=C.UTF-8 make test
make install 
chmod 644 /usr/lib/libtclstub8.6.a
make install-private-headers
ln -sfv tclsh8.6 /usr/bin/tclsh
cd ..
cd ..
rm -rfv tcl8.6.17

tar -xf patch-2.8.tar.xz
cd patch-2.8
./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv patch-2.8

tar -xf expect5.45.4.tar.gz
cd expect5.45.4
patch -Np1 -i ../expect-5.45.4-gcc15-1.patch
./configure --prefix=/usr --with-tcl=/usr/lib --enable-shared --disable-rpath --with-tclinclude=/usr/include
make
# make test
make install
ln -svf expect5.45.4/libexpect5.45.4.so /usr/lib
cd ..
rm -rfv expect5.45.4

tar -xf dejagnu-1.6.3.tar.gz
cd dejagnu-1.6.3
mkdir -v Build
cd Build
../configure --prefix=/usr
# make check
make install
cd ..
cd ..
rm -rfv dejagnu-1.6.3

tar -xf pkgconf-2.5.1.tar.xz
cd pkgconf-2.5.1
./configure --prefix=/usr
make
make install
ln -sv pkgconf   /usr/bin/pkg-config
cd ..
rm -rfv pkgconf-2.5.1

cd binutils-2.46.0
mkdir -v Build
cd Build
../configure --prefix=/usr --sysconfdir=/etc --enable-ld=default --enable-plugins --enable-shared --disable-werror --enable-64-bit-bfd --enable-new-dtags --with-system-zlib --enable-default-hash-style=gnu
make tooldir=/usr
# make -k check
# grep '^FAIL:' $(find -name '*.log')
make tooldir=/usr install
rm -rfv /usr/share/doc/gprofng/
cd ..
cd ..
rm -rfv binutils-2.46.0 

tar -xf gmp-6.3.0.tar.xz
cd gmp-6.3.0
sed -i '/long long t1;/,+1s/()/(...)/' configure
./configure --prefix=/usr --enable-cxx --host=none-linux-gnu
make
# make check 2>&1 | tee gmp-check-log
# awk '/# PASS:/{total+=$3} ; END{print total}' gmp-check-log
make install
cd ..
rm -rfv gmp-6.3.0

tar -xf mpfr-4.2.2.tar.xz
cd mpfr-4.2.2
./configure --prefix=/usr --enable-thread-safe
make
# make check
make install
cd ..
rm -rfv mpfr-4.2.2

tar -xf mpc-1.3.1.tar.gz
cd mpc-1.3.1
./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv mpc-1.3.1

tar -xf attr-2.5.2.tar.gz
cd attr-2.5.2
./configure --prefix=/usr --sysconfdir=/etc
# Fix for Musl.
sed -i '31i #include <libgen.h>' tools/attr.c
make
# make check
make install
cd ..
rm -rfv attr-2.5.2

tar -xf acl-2.3.2.tar.xz
cd acl-2.3.2
./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv acl-2.3.2

tar -xf libcap-2.77.tar.xz
cd libcap-2.77
make prefix=/usr lib=lib
# make test
make prefix=/usr lib=lib install
cd ..
rm -rfv libcap-2.77

tar -xf libxcrypt-4.5.2.tar.xz
cd libxcrypt-4.5.2
./configure --prefix=/usr --enable-hashes=strong --enable-obsolete-api=no --disable-failure-tokens
make
# make check
make install
cd ..
rm -rfv libxcrypt-4.5.2

tar -xf shadow-4.19.3.tar.xz
cd shadow-4.19.3
sed -i 's/groups$(EXEEXT) //' src/Makefile.in
find man -name Makefile.in -exec sed -i 's/groups\.1 / /'   {} \;
find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;
sed -e 's:#ENCRYPT_METHOD DES:ENCRYPT_METHOD YESCRYPT:' \
    -e 's:/var/spool/mail:/var/mail:'                   \
    -e '/PATH=/{s@/sbin:@@;s@/bin:@@}'                  \
    -i etc/login.defs
touch /usr/bin/passwd
./configure --sysconfdir=/etc --with-{b,yes}crypt --without-libbsd --disable-logind --with-group-name-max-length=32
make
make exec_prefix=/usr install
cd ..
rm -rfv shadow-4.19.3.tar.xz
pwconv
grpconv
mkdir -p /etc/default
useradd -D --gid 999

cd gcc-15.2.0
case $(uname -m) in
  x86_64) sed -e '/m64=/s/lib64/lib/' -i.orig gcc/config/i386/t-linux64;;
esac
mkdir -v Build
cd Build
../configure --prefix=/usr LD=ld --enable-languages=c,c++ --enable-default-pie --enable-default-ssp --enable-host-pie --disable-multilib --disable-bootstrap --disable-fixincludes --with-system-zlib
make
# sed -e '/cpython/d' -i ../gcc/testsuite/gcc.dg/plugin/plugin.exp
# chown -R tester .
# su tester -c "PATH=$PATH make -k check"
# ../contrib/test_summary
make install
# chown -v -R root:root /usr/lib/gcc/$(gcc -dumpmachine)/15.2.0/include{,-fixed}
ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/15.2.0/liblto_plugin.so /usr/lib/bfd-plugins/
mkdir -pv /usr/share/gdb/auto-load/usr/lib
mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib
cd ..
cd ..
rm -rfv gcc-15.2.0

tar -xf ncurses-6.6.tar.gz
cd ncurses-6.6
./configure --prefix=/usr --with-shared --without-debug --with-cxx-binding --with-cxx-shared --enable-pc-files --with-pkg-config-libdir=/usr/lib/pkgconfig
make
make DESTDIR=$PWD/dest install
sed -e 's/^#if.*XOPEN.*$/#if 1/' -i dest/usr/include/curses.h
cp --remove-destination -av dest/* /
for lib in ncurses form panel menu ; do
    ln -sfv lib${lib}w.so /usr/lib/lib${lib}.so
    ln -sfv ${lib}w.pc    /usr/lib/pkgconfig/${lib}.pc
done
ln -sfv libncursesw.so /usr/lib/libcurses.so
cd ..
rm -rfv ncurses-6.6

tar -xf sed-4.9.tar.xz
cd sed-4.9
./configure --prefix=/usr
make
# chown -R tester .
# su tester -c "PATH=$PATH make check"
make install
cd ..
rm -rfv sed-4.9

tar -xf psmisc-23.7.tar.xz
cd psmisc-23.7
./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv psmisc-23.7

tar -xf bison-3.8.2.tar.xz
cd bison-3.8.2
./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv bison-3.8.2

tar -xf grep-3.12.tar.xz
cd grep-3.12
# sed -i "s/echo/#echo/" src/egrep.sh
./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv grep-3.12

tar -xf bash-5.3.tar.gz
cd bash-5.3
./configure --prefix=/usr --without-bash-malloc --with-installed-readline
make
# chown -R tester .
# LC_ALL=C.UTF-8 su -s /usr/bin/expect tester << "EOF"
# set timeout -1
# spawn make tests
# expect eof
# lassign [wait] _ _ _ value
# exit $value
# EOF
make install
cd ..
rm -rfv bash-5.3

# Rather than doing "exec /usr/bin/bash --login" as in the Book, we leave the Chroot and enter it again.
logout

elif [[ $STEP = "Build3" ]]; then
cd /sources

# Lfs 8, Continued.

tar -xf libtool-2.5.4.tar.xz
cd libtool-2.5.4
./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv libtool-2.5.4

tar -xf gdbm-1.26.tar.gz
cd gdbm-1.26
./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv gdbm-1.26

tar -xf gperf-3.3.tar.gz
cd gperf-3.3
./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv gperf-3.3

tar -xf expat-2.7.4.tar.xz
cd expat-2.7.4
./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv expat-2.7.4

tar -xf less-692.tar.gz
cd less-692
./configure --prefix=/usr --sysconfdir=/etc
make
# make check
make install
cd ..
rm -rfv less-692

tar -xf perl-5.42.0.tar.xz
cd perl-5.42.0
export BUILD_ZLIB=False
export BUILD_BZIP2=0
# Musl needs that AccFlag.
sh Configure -des -D prefix=/usr -D vendorprefix=/usr -D privlib=/usr/lib/perl5/5.42/core_perl -D archlib=/usr/lib/perl5/5.42/core_perl -D sitelib=/usr/lib/perl5/5.42/site_perl -D sitearch=/usr/lib/perl5/5.42/site_perl -D vendorlib=/usr/lib/perl5/5.42/vendor_perl -D vendorarch=/usr/lib/perl5/5.42/vendor_perl -D useshrplib -D usethreads -Accflags="-D_GNU_SOURCE"
make
# TEST_JOBS=$(nproc) make test_harness
make install
unset BUILD_ZLIB BUILD_BZIP2
cd ..
rm -rfv perl-5.42.0

tar -xf XML-Parser-2.47.tar.gz
cd XML-Parser-2.47
perl Makefile.PL
make
# make test
make install
cd ..
rm -rfv XML-Parser-2.47

tar -xf autoconf-2.72.tar.xz
cd autoconf-2.72
./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv autoconf-2.72

tar -xf automake-1.18.1.tar.xz
cd automake-1.18.1
./configure --prefix=/usr
make
# make -j$(($(nproc)>4?$(nproc):4)) check
make install
cd ..
rm -rfv automake-1.18.1

tar -xf openssl-3.6.1.tar.gz
cd openssl-3.6.1
./config --prefix=/usr --openssldir=/etc/ssl --libdir=lib
make
# HARNESS_JOBS=$(nproc) make test
make install
cd ..
rm -rfv openssl-3.6.1

# ElfUtils cannot be built with Musl for now, use Third Party Standalone LibElf.
tar -xf libelf-0.193.tar.gz
cd libelf-0.193
make
make PREFIX=/usr install
cd ..
rm -rfv libelf-0.193

tar -xf libffi-3.5.2.tar.gz
cd libffi-3.5.2
./configure --prefix=/usr --without-gcc-arch
make
# make check
make install
cd ..
rm -rfv libffi-3.5.2

tar -xf sqlite-autoconf-3510200.tar.gz
cd sqlite-autoconf-3510200
./configure --prefix=/usr --enable-fts{4,5} CPPFLAGS="-D SQLITE_ENABLE_COLUMN_METADATA=1 -D SQLITE_ENABLE_UNLOCK_NOTIFY=1 -D SQLITE_ENABLE_DBSTAT_VTAB=1 -D SQLITE_SECURE_DELETE=1"
make LDFLAGS.rpath=""
make install
cd ..
rm -rfv sqlite-autoconf-3510200

tar -xf Python-3.14.3.tar.xz
cd Python-3.14.3
./configure --prefix=/usr --enable-shared --with-system-expat --enable-optimizations --without-static-libpython
make
# make test TESTOPTS="--timeout 120"
make install
cd ..
rm -rfv Python-3.14.3

tar -xf flit_core-3.12.0.tar.gz
cd flit_core-3.12.0
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist flit_core
cd ..
rm -rfv flit_core-3.12.0

tar -xf packaging-26.0.tar.gz
cd packaging-26.0
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist packaging
cd ..
rm -rfv packaging-26.0

tar -xf wheel-0.46.3.tar.gz
cd wheel-0.46.3
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist wheel
cd ..
rm -rfv wheel-0.46.3

tar -xf setuptools-82.0.0.tar.gz
cd setuptools-82.0.0
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist setuptools
cd ..
rm -rfv setuptools-82.0.0

tar -xf ninja-1.13.2.tar.gz
cd ninja-1.13.2
python3 configure.py --bootstrap --verbose
install -vm755 ninja /usr/bin/
cd ..
rm -rfv ninja-1.13.2

tar -xf meson-1.10.1.tar.gz
cd meson-1.10.1
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist meson
cd ..
rm -rfv meson-1.10.1

tar -xf kmod-34.2.tar.xz
cd kmod-34.2
mkdir Build
cd Build
meson setup --prefix=/usr .. --buildtype=release -D manpages=false
ninja
ninja install
cd ..
cd ..
rm -rfv kmod-34.2

tar -xf coreutils-9.10.tar.xz
cd coreutils-9.10
autoreconf -fv
automake -af
FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr --disable-manpages
make
# make NON_ROOT_USERNAME=tester check
# groupadd -g 102 dummy -U tester
# chown -R tester .
# su tester -c "PATH=$PATH make -k RUN_EXPENSIVE_TESTS=yes check" < /dev/null
# groupdel dummy
make install
mv -v /usr/bin/chroot /usr/sbin
cd ..
rm -rfv coreutils-9.10

tar -xf diffutils-3.12.tar.xz
cd diffutils-3.12
./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv diffutils-3.12

tar -xf gawk-5.3.2.tar.xz
cd gawk-5.3.2
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr
make
# chown -R tester .
# su tester -c "PATH=$PATH make check"
rm -f /usr/bin/gawk-5.3.2
make install
cd ..
rm -rfv gawk-5.3.2

tar -xf findutils-4.10.0.tar.xz
cd findutils-4.10.0
./configure --prefix=/usr
make
# chown -R tester .
# su tester -c "PATH=$PATH make check"
make install
cd ..
rm -rfv findutils-4.10.0

# Grub for Efi requires EfiVar, PopT and EfiBootMgr from BLfs.
tar -xf efivar-39.tar.gz
cd efivar-39
make ENABLE_DOCS=0
make install ENABLE_DOCS=0 LIBDIR=/usr/lib
cd ..
rm -rfv efivar-39

tar -xf popt-1.19.tar.gz
cd popt-1.19
./configure --prefix=/usr
make
make install
cd ..
rm -rfv popt-1.19

tar -xf efibootmgr-18.tar.gz
cd efibootmgr-18
make EFIDIR=LfsOs EFI_LOADER=grubx64.efi
make install EFIDIR=LfsOs
cd ..
rm -rfv efibootmgr-18

tar -xf grub-2.14.tar.xz
cd grub-2.14
# Fix for Musl.
sed -i '/# include <sys\/cdefs.h>/d' grub-core/lib/gnulib/getopt-cdefs.h
./configure --prefix=/usr --sysconfdir=/etc --disable-efiemu --with-platform=efi --target=x86_64 --disable-werror
make
make install
cd ..
rm -rfv grub-2.14

tar -xf gzip-1.14.tar.xz
cd gzip-1.14
./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv gzip-1.14

tar -xf kbd-2.9.0.tar.xz
cd kbd-2.9.0
sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure
./configure --prefix=/usr --disable-vlock
make
# make check
make install
cd ..
rm -rfv kbd-2.9.0

tar -xf make-4.4.1.tar.gz
cd make-4.4.1
# Fixes for Musl.
sed -i -e 's/getenv ();/getenv (const char *);/g' lib/fnmatch.c
sed -i -e 's/getenv ();/getenv (const char *);/g' src/getopt.c
sed -i -e 's/getopt ();/getopt (int,  char * const*, const char *);/g' src/getopt.h
./configure --prefix=/usr
make
# chown -R tester .
# su tester -c "PATH=$PATH make check"
make install
cd ..
rm -rfv make-4.4.1

tar -xf tar-1.35.tar.xz
cd tar-1.35
FORCE_UNSAFE_CONFIGURE=1 ./configure --prefix=/usr
make
# make check
make install
cd ..
rm -rfv tar-1.35

tar -xf markupsafe-3.0.3.tar.gz
cd markupsafe-3.0.3
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist Markupsafe
cd ..
rm -rfv markupsafe-3.0.3

tar -xf jinja2-3.1.6.tar.gz
cd jinja2-3.1.6
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist Jinja2
cd ..
rm -rfv jinja2-3.1.6

tar -xf systemd-259.1.tar.gz
cd systemd-259.1
sed -e 's/GROUP="render"/GROUP="video"/' -e 's/GROUP="sgx", //' -i rules.d/50-udev-default.rules.in
# Fixes SystemD Boot Errors with Musl. From a "Do-not-disable-buffering-when-writing-to-oom_score_a" Patch which original source is unknown.
sed -i 's/WRITE_STRING_FILE_VERIFY_ON_FAILURE|WRITE_STRING_FILE_DISABLE_BUFFER/WRITE_STRING_FILE_VERIFY_ON_FAILURE/g' src/basic/process-util.c
mkdir Build
cd Build
# Musl needs the libc=musl Option.
meson setup .. --prefix=/usr --buildtype=release -D default-dnssec=no -D firstboot=false -D install-tests=false -D ldconfig=false -D sysusers=false -D rpmmacrosdir=no -D homed=disabled -D man=disabled -D mode=release -D pamconfdir=no -D dev-kvm-mode=0660 -D nobody-group=nogroup -D sysupdate=disabled -D ukify=disabled -D libc=musl
ninja
# echo 'NAME="LfsOs"' > /etc/os-release
# unshare -m ninja test
ninja install
systemd-machine-id-setup
systemctl preset-all
cd ..
cd ..
rm -rfv systemd-259.1

tar -xf procps-ng-4.0.6.tar.xz
cd procps-ng-4.0.6
./configure --prefix=/usr --disable-kill --enable-watch8bit --with-systemd
make
# chown -R tester .
# su tester -c "PATH=$PATH make check"
make install
cd ..
rm -rfv procps-ng-4.0.6

tar -xf util-linux-2.41.3.tar.xz
cd util-linux-2.41.3
./configure --bindir=/usr/bin --libdir=/usr/lib --runstatedir=/run --sbindir=/usr/sbin --disable-chfn-chsh --disable-login --disable-nologin --disable-su --disable-setpriv --disable-runuser --disable-pylibmount --disable-liblastlog2 --without-python ADJTIME_PATH=/var/lib/hwclock/adjtime
make
# touch /etc/fstab
# chown -R tester .
# su tester -c "make -k check"
make install
cd ..
rm -rfv util-linux-2.41.3

tar -xf e2fsprogs-1.47.3.tar.gz
cd e2fsprogs-1.47.3
mkdir -v Build
cd Build
../configure --prefix=/usr --sysconfdir=/etc --enable-elf-shlibs --disable-libblkid --disable-libuuid --disable-uuidd --disable-fsck
make
# make check
make install
cd ..
cd ..
rm -rfv e2fsprogs-1.47.3

tar -xf nano-8.7.1.tar.xz
cd nano-8.7.1
./configure --prefix=/usr --sysconfdir=/etc --enable-utf8
make
make install
cd ..
rm -rfv nano-8.7.1

# Lfs 8.xx: Clean Up
rm -rfv /tmp/{*,.*}
find /usr/lib /usr/libexec -name \*.la -delete
find /usr -depth -name $(uname -m)-lfs-linux-musl\* | xargs rm -rf
# userdel -r tester

# Lfs 9: System Configuration.

# Root Password so we can Login in the First Boot. Of course change it if actually using the System, create Users, etc.
echo "root:root" | chpasswd

# Lfs 9.2: Disable Networking, Configuration left to the User.
systemctl disable systemd-networkd-wait-online
systemctl disable systemd-resolved

# HostName.
echo "LfsOs" > /etc/hostname

# Lfs 10.2: Create /etc/fstab.
echo "# file system                             mount-point  type     options           dump  fsck order" > /etc/fstab
echo "UUID=$(blkid -s UUID -o value ${LOOP}p2) /            ext4     defaults          1     1" >> /etc/fstab

# Lfs 10.3: Configure and Build Kernel.
# DefConfig loads some default .config File, then Options recommnded by Lfs are appended to override the defaults, and OldDefConfig rebuilds the .config with missing values without prompting.
tar -xf linux-6.18.10.tar.xz
cd linux-6.18.10
make mrproper
make defconfig
echo "CONFIG_WERROR=n" >> .config
echo "CONFIG_PSI=y" >> .config
echo "CONFIG_PSI_DEFAULT_DISABLED=n" >> .config
echo "CONFIG_IKHEADERS=n" >> .config
echo "CONFIG_CGROUPS=y" >> .config
echo "CONFIG_MEMCG=y" >> .config
echo "CONFIG_CGROUP_SCHED=y" >> .config
echo "CONFIG_RT_GROUP_SCHED=n" >> .config
echo "CONFIG_EXPERT=n" >> .config
echo "CONFIG_RELOCATABLE=y" >> .config
echo "CONFIG_RANDOMIZE_BASE=y" >> .config
echo "CONFIG_STACKPROTECTOR=y" >> .config
echo "CONFIG_STACKPROTECTOR_STRONG=y" >> .config
echo "CONFIG_NET=y" >> .config
echo "CONFIG_INET=y" >> .config
echo "CONFIG_IPV6=y" >> .config
echo "CONFIG_UEVENT_HELPER=n" >> .config
echo "CONFIG_DEVTMPFS=y" >> .config
echo "CONFIG_DEVTMPFS_MOUNT=y" >> .config
echo "CONFIG_FW_LOADER=y" >> .config
echo "CONFIG_FW_LOADER_USER_HELPER=n" >> .config
echo "CONFIG_FW_DMIID=y" >> .config
echo "CONFIG_SYSFB_SIMPLEFB=y" >> .config
echo "CONFIG_DRM=y" >> .config
echo "CONFIG_DRM_PANIC=y" >> .config
echo "CONFIG_DRM_PANIC_SCREEN=kmsg" >> .config
echo "CONFIG_DRM_FBDEV_EMULATION=y" >> .config
echo "CONFIG_DRM_SIMPLEDRM=y" >> .config
echo "CONFIG_FRAMEBUFFER_CONSOLE=y" >> .config
echo "CONFIG_INOTIFY_USER=y" >> .config
echo "CONFIG_TMPFS=y" >> .config
echo "CONFIG_TMPFS_POSIX_ACL=y" >> .config
echo "CONFIG_BLK_DEV_NVME=y" >> .config
echo "CONFIG_EFI=y" >> .config
echo "CONFIG_EFI_STUB=y" >> .config
echo "CONFIG_BLOCK=y" >> .config
echo "CONFIG_PARTITION_ADVANCED=y" >> .config
echo "CONFIG_EFI_PARTITION=y" >> .config
echo "CONFIG_VFAT_FS=y" >> .config
echo "CONFIG_EFIVAR_FS=y" >> .config
echo "CONFIG_NLS=y" >> .config
echo "CONFIG_NLS_CODEPAGE_437=y" >> .config
echo "CONFIG_NLS_NLS_ISO8859_1=y" >> .config
case $(uname -m) in
	i?86)   echo "CONFIG_HIGHMEM4G=y" >> .config
	;;
	x86_64) echo "CONFIG_X86_X2APIC=y" >> .config
	        echo "CONFIG_PCI=y" >> .config
	        echo "CONFIG_PCI_MSI=y" >> .config
	        echo "CONFIG_IOMMU_SUPPORT=y" >> .config
	        echo "CONFIG_IRQ_REMAP=y" >> .config
	;;
esac
make olddefconfig
make
make modules_install
cp -iv arch/x86/boot/bzImage /boot/vmlinuz-6.18.10-LfsOs
cp -iv System.map /boot/System.map-6.18.10
cp -iv .config /boot/config-6.18.10
install -v -m755 -d /etc/modprobe.d
cat > /etc/modprobe.d/usb.conf << "EOF"
install ohci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i ohci_hcd ; true
install uhci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i uhci_hcd ; true
EOF
cd ..
rm -rfv linux-6.18.10

# BLfs grub-setup: Grub Efi Setup.

mount --mkdir -v -t vfat ${LOOP}p1 -o codepage=437,iocharset=iso8859-1 /boot/efi
mount -v -t efivarfs efivarfs /sys/firmware/efi/efivars
cat >> /etc/fstab << EOF
efivarfs /sys/firmware/efi/efivars efivarfs defaults 0 0
EOF

grub-install --target=x86_64-efi --removable
umount /boot/efi

cat > /boot/grub/grub.cfg << EOF
set default=0
set timeout=5

insmod part_gpt
insmod ext2
set --set=root --fs-uuid UuId

insmod efi_gop

menuentry "LfsOs" {
	linux /boot/vmlinuz-6.18.10-LfsOs root=PARTUUID=PartUuId ro
}

menuentry "Firmware Setup" {
	fwsetup
}
EOF
sed -i "s/PartUuId/$(blkid -s PARTUUID -o value ${LOOP}p2)/g" /boot/grub/grub.cfg
sed -i "s/UuId/$(blkid -s UUID -o value ${LOOP}p2)/g" /boot/grub/grub.cfg

logout

# Run this manually if Script aborted Early.
elif [[ $STEP = "CleanUp" ]]; then

# Delete Temporary User (if not already done).
if id $LFSUSER >/dev/null 2>&1; then
	userdel -r $LFSUSER
fi

# Unmount if Not Mounted.
mountpoint -q $LFS/dev/pts && umount -v $LFS/dev/pts
mountpoint -q $LFS/dev/shm && umount -v $LFS/dev/shm
mountpoint -q $LFS/dev && umount -v $LFS/dev
mountpoint -q $LFS/run && umount -v $LFS/run
mountpoint -q $LFS/proc && umount -v $LFS/proc
mountpoint -q $LFS/sys && umount -v $LFS/sys
mountpoint -q $LFS/boot/efi && umount -v $LFS/boot/efi
mountpoint -q $LFS && umount -v $LFS
losetup -d $LOOP

else
	echo "Invalid Step!"
fi
