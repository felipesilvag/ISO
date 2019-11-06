#!/bin/sh

cwd="`realpath | sed 's|/scripts||g'`"
workdir="/usr/local"
livecd="${workdir}/furybsd"
cache="${livecd}/cache"
version="12.0"
arch=AMD64
base="${cache}/${version}/base"
packages="${cache}/packages"
ports="${cache}/ports"
iso="${livecd}/iso"
uzip="${livecd}/uzip"
cdroot="${livecd}/cdroot"
ramdisk_root="${cdroot}/data/ramdisk"
vol="furybsd"
label="FURYBSD"
isopath="${iso}/${vol}.iso"
desktop=$1

# Only run as superuser
if [ "$(id -u)" != "0" ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

case $desktop in
  'kde')
    export desktop="kde"
    export edition="KDE"
    ;;
  'gnome')
    export desktop="gnome"
    export edition="GNOME"
    ;;
  *)
    export desktop="xfce"
    export edition="XFCE"
    ;;
esac

vol="FuryBSD-${version}-${edition}"
label="FURYBSD"
isopath="${iso}/${vol}.iso"

workspace()
{
  umount ${uzip}/var/cache/pkg >/dev/null 2>/dev/null
  umount ${uzip}/usr/ports >/dev/null 2>/dev/null
  umount ${uzip}/dev >/dev/null 2>/dev/null
  if [ -d "${livecd}" ] ;then
    chflags -R noschg ${uzip} ${cdroot} >/dev/null 2>/dev/null
    rm -rf ${uzip} ${cdroot} >/dev/null 2>/dev/null
  fi
  mkdir -p ${livecd} ${base} ${iso} ${packages} ${ports} ${uzip} ${ramdisk_root}/dev ${ramdisk_root}/etc >/dev/null 2>/dev/null
}

base()
{
  if [ ! -f "${base}/base.txz" ] ; then 
    cd ${base}
    fetch http://ftp.freebsd.org/pub/FreeBSD/releases/amd64/${version}-RELEASE/base.txz
  fi
  
  if [ ! -f "${base}/kernel.txz" ] ; then
    cd ${base}
    fetch http://ftp.freebsd.org/pub/FreeBSD/releases/amd64/${version}-RELEASE/kernel.txz
  fi
  cd ${base}
  tar -zxvf base.txz -C ${uzip}
  tar -zxvf kernel.txz -C ${uzip}
  touch ${uzip}/etc/fstab
}

packages()
{
  cp /etc/resolv.conf ${uzip}/etc/resolv.conf
  mkdir ${uzip}/var/cache/pkg
  mount_nullfs ${packages} ${uzip}/var/cache/pkg
  mount -t devfs devfs ${uzip}/dev
  cat ${cwd}/settings/packages.common | xargs pkg-static -c ${uzip} install -y
  cat ${cwd}/settings/packages.${desktop} | xargs pkg-static -c ${uzip} install -y
  rm ${uzip}/etc/resolv.conf
  umount ${uzip}/var/cache/pkg
  umount ${uzip}/dev || true
}

ports()
{
  if [ -d ${ports}/Mk ] ; then
    portsnap fetch update
  else
    portsnap fetch extract
  fi
  cp /etc/resolv.conf ${uzip}/etc/resolv.conf
  mount_nullfs ${packages} ${uzip}/var/cache/pkg
  mkdir ${uzip}/usr/ports
  mount_nullfs ${ports} ${uzip}/usr/ports
  mount -t devfs devfs ${uzip}/dev
  cd ${uzip} && fetch https://github.com/furybsd/furybsd-ports/archive/master.zip
  chroot ${uzip} tar -xf master.txz
  chroot ${uzip} cd /furybsd-ports-master && sh ./mkports.sh
  chroot ${uzip} cd /usr/ports/x11-themes/furybsd-artwork && make install clean
  rm -rf ${uzip}/furybsd-ports-master/
  rm ${uzip}/master.zip
  rm ${uzip}/etc/resolv.conf
  umount ${uzip}/var/cache/pkg
  umount ${uzip}/usr/ports >/dev/null 2>/dev/null
  umount ${uzip}/dev || true
}

rc()
{
  if [ ! -f "${uzip}/etc/rc.conf" ] ; then
    touch ${uzip}/etc/rc.conf
  fi
  if [ ! -f "${uzip}/etc/rc.conf.local" ] ; then
    touch ${uzip}/etc/rc.conf.local
  fi
  cat ${cwd}/settings/rc.conf.common | xargs chroot ${uzip} sysrc -f /etc/rc.conf.local
  cat ${cwd}/settings/rc.conf.${desktop} | xargs chroot ${uzip} sysrc -f /etc/rc.conf.local
}

user()
{
  mkdir -p ${uzip}/usr/home/liveuser/Desktop
  cp ${cwd}/fury-install ${uzip}/usr/home/liveuser/
  cp -R ${cwd}/xorg.conf.d/ ${uzip}/usr/home/liveuser/xorg.conf.d
  cp ${cwd}/fury-config.desktop ${uzip}/usr/home/liveuser/Desktop/
  cp ${cwd}/fury-install.desktop ${uzip}/usr/home/liveuser/Desktop/
  cp ${cwd}/fury-desktop-readme.txt ${uzip}/usr/home/liveuser/Desktop/"Getting Started.txt"
  chroot ${uzip} echo furybsd | chroot ${uzip} pw mod user root -h 0
  chroot ${uzip} pw useradd liveuser -u 1000 \
  -c "Live User" -d "/home/liveuser" \
  -g wheel -G operator -m -s /bin/csh -k /usr/share/skel -w none
  chroot ${uzip} pw groupadd liveuser -g 1000
  chroot ${uzip} echo furybsd | chroot ${uzip} pw mod user liveuser -h 0
  chroot ${uzip} chown -R 1000:1000 /usr/home/liveuser
  cp ${cwd}/doas.conf ${uzip}/usr/local/etc/
}

dm()
{
  case $desktop in
    'kde')
      cp ${cwd}/sddm.conf ${uzip}/usr/local/etc/
      ;;
    'gnome')
      cp ${cwd}/custom.conf $[uzip}/usr/local/etc/gdm/
      ;;
    *)
      cp ${cwd}/lightdm.conf ${uzip}/usr/local/etc/lightdm/
      chroot ${uzip} sed -i '' -e 's/memorylocked=128M/memorylocked=256M/' /etc/login.conf
      chroot ${uzip} cap_mkdb /etc/login.conf
      ;;
  esac
}

uzip() 
{
  install -o root -g wheel -m 755 -d "${cdroot}"
  makefs "${cdroot}/data/system.ufs" "${uzip}"
  mkuzip -o "${cdroot}/data/system.uzip" "${cdroot}/data/system.ufs"
  rm -f "${cdroot}/data/system.ufs"
}

ramdisk() 
{
  cp -R ${cwd}/overlays/ramdisk/ ${ramdisk_root}
  cd "${uzip}" && tar -cf - rescue | tar -xf - -C "${ramdisk_root}"
  touch "${ramdisk_root}/etc/fstab"
  cp ${uzip}/etc/login.conf ${ramdisk_root}/etc/login.conf
  makefs -b '10%' "${cdroot}/data/ramdisk.ufs" "${ramdisk_root}"
  gzip "${cdroot}/data/ramdisk.ufs"
  rm -rf "${ramdisk_root}"
}

boot() 
{
  cp -R ${cwd}/overlays/boot/ ${cdroot}
  cd "${uzip}" && tar -cf - --exclude boot/kernel boot | tar -xf - -C "${cdroot}"
  for kfile in kernel geom_uzip.ko nullfs.ko tmpfs.ko unionfs.ko; do
  tar -cf - boot/kernel/${kfile} | tar -xf - -C "${cdroot}"
  done
}

image() 
{
  sh ${cwd}/scripts/mkisoimages.sh -b $label $isopath ${cdroot}
}

cleanup()
{
  if [ -d "${livecd}" ] ; then
    chflags -R noschg ${uzip} ${cdroot} >/dev/null 2>/dev/null
    rm -rf ${uzip} ${cdroot} >/dev/null 2>/dev/null
  fi
}

workspace
base
packages
ports
rc
dm
user
uzip
ramdisk
boot
image
cleanup
