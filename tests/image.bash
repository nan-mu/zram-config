#!/usr/bin/env bash

imageFile() {
  local loopPrefix

  if [[ $1 == "mount" ]]; then
    loopPrefix="$(kpartx -asv "$2" | grep -oE "loop([0-9]+)" | head -n 1)"

    mkdir -p tests/{fs,kernel}
    if [[ "$2" == "alpine-rpi-3.20.1-armhf.img" ]]; then
      mount -o rw -t vfat "/dev/mapper/${loopPrefix}p1" "tests/fs"
    else
      mount -o rw -t ext4 "/dev/mapper/${loopPrefix}p2" "tests/fs"
      mount -o rw -t vfat "/dev/mapper/${loopPrefix}p1" "tests/fs/boot"
    fi
  elif [[ $1 == "umount" ]]; then
    sync
    [[ "$2" == "alpine-rpi-3.20.1-armhf.img" ]] || umount tests/fs/boot
    umount tests/fs
    kpartx -d "$2"
  fi
}

if [[ $1 == "setup" ]]; then
  if ! [[ -f $3 ]]; then
    if [[ "$3" == "alpine-rpi-3.20.1-armhf.img" ]]; then
      curl -s -L "https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/armhf/alpine-rpi-3.20.1-armhf.img.gz" -o "$2"
      curl -s https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/armhf/alpine-rpi-3.20.1-armhf.img.gz.asc -o "${2}.asc"
      gpg -q --keyserver keyserver.ubuntu.com --recv-key 0x0482D84022F52DF1C4E7CD43293ACD0907D9495A
      gpg -q --trust-model always --verify "${2}.asc" "$2"
      gzip "$2" -d
    else
      curl -s -L "https://downloads.raspberrypi.org/raspios_lite_armhf_latest" -o "$2"
      curl -s "$(curl "https://downloads.raspberrypi.org/raspios_lite_armhf_latest" -s -L -I  -o /dev/null -w '%{url_effective}')".sig -o "${2}.sig"
      gpg -q --keyserver keyserver.ubuntu.com --recv-key 0x8738CD6B956F460C
      gpg -q --trust-model always --verify "${2}.sig" "$2"
      xz "$2" -d
    fi
  fi
  qemu-img resize -f raw "$3" 4G
  if [[ "$3" == "alpine-rpi-3.20.1-armhf.img" ]]; then
    echo ", +" | sfdisk -N 1 "$3"
  else 
    echo ", +" | sfdisk -N 2 "$3"
  fi
  imageFile "mount" "$3"
  [[ -d tests/fs/opt ]] || mkdir -p tests/fs/opt
  rsync -avr --exclude="*.img" --exclude="*.sig" --exclude="*.asc" --exclude="tests/fs" --exclude="*.dtb" --exclude="tests/kernel" ./ tests/fs/opt/zram
  if [[ "$3" != "alpine-rpi-3.20.1-armhf.img" ]]; then 
    systemd-nspawn --directory="tests/fs" /opt/zram/tests/install-packages.bash
 q   echo "set enable-bracketed-paste off" >> tests/fs/etc/inputrc  # Prevents weird character output
    cp tests/fs/boot/kernel* tests/kernel
  else
    cp tests/fs/boot/vmlinuz-rpi /tests/kernel
    curl -s -L "https://dl-cdn.alpinelinux.org/alpine/v3.20/main/armhf/bash-5.2.26-r0.apk" -o "tests/fs/opt/bash-5.2.26-r0.apk" 
    curl -s -L "https://dl-cdn.alpinelinux.org/alpine/v3.20/main/armhf/gcc-13.2.1_git20240309-r0.apk" -o "tests/fs/opt/gcc-13.2.1_git20240309-r0.apk" 
  fi
  # Compile a customized DTB
  git clone https://github.com/raspberrypi/utils.git
  cmake utils/dtmerge
  make
  sudo make install
  dtmerge tests/fs/boot/bcm2710-rpi-3-b-plus.dtb custom.dtb tests/fs/boot/overlays/disable-bt.dtbo uart0=on
  imageFile "umount" "$3"
elif [[ $1 == "copy-logs" ]]; then
  imageFile "mount" "$2"
  cp tests/fs/opt/zram/logs.tar .
  imageFile "umount" "$2"
fi

exit 0
