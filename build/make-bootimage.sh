#!/bin/bash
set -ex

TMPDOWN=$(realpath $1)
KERNEL_OUT=$(realpath $2)
RAMDISK=$(realpath $3)
OUT=$(realpath $4)

HERE=$(pwd)

if [ ! -z $DEVICE ]; then
source "${HERE}/deviceinfo-${DEVICE}"
else
source "${HERE}/deviceinfo"
fi


case "$deviceinfo_arch" in
    aarch64*) ARCH="arm64" ;;
    arm*) ARCH="arm" ;;
    x86_64) ARCH="x86_64" ;;
    x86) ARCH="x86" ;;
esac

[ -f "$HERE/ramdisk-recovery.img" ] && RECOVERY_RAMDISK="$HERE/ramdisk-recovery.img"
[ -f "$HERE/ramdisk-overlay/ramdisk-recovery.img" ] && RECOVERY_RAMDISK="$HERE/ramdisk-overlay/ramdisk-recovery.img"

if [ -d "$HERE/ramdisk-recovery-overlay" ] && [ -e "$RECOVERY_RAMDISK" ]; then
    mkdir -p "$HERE/ramdisk-recovery"

    cd "$HERE/ramdisk-recovery"
    gzip -dc "$RECOVERY_RAMDISK" | cpio -i
    cp -r "$HERE/ramdisk-recovery-overlay"/* "$HERE/ramdisk-recovery"

    find . | cpio -o -H newc | gzip > "$RECOVERY_RAMDISK"
fi

if [ -d "$HERE/ramdisk-overlay" ]; then
    cp "$RAMDISK" "${RAMDISK}-merged"
    RAMDISK="${RAMDISK}-merged"
    cd "$HERE/ramdisk-overlay"
    find . | cpio -o -H newc | gzip >> "$RAMDISK"
fi

if [ -n "$deviceinfo_kernel_image_name" ]; then
    KERNEL="$KERNEL_OUT/arch/$ARCH/boot/$deviceinfo_kernel_image_name"
else
    # Autodetect kernel image name for boot.img
    if [ "$deviceinfo_bootimg_header_version" -eq 2 ]; then
        IMAGE_LIST="Image.gz Image"
    else
        IMAGE_LIST="Image.gz-dtb Image.gz Image"
    fi

    for image in $IMAGE_LIST; do
        if [ -e "$KERNEL_OUT/arch/$ARCH/boot/$image" ]; then
            KERNEL="$KERNEL_OUT/arch/$ARCH/boot/$image"
            break
        fi
    done
fi

if [ -n "$deviceinfo_bootimg_prebuilt_dtb" ]; then
    DTB="$HERE/$deviceinfo_bootimg_prebuilt_dtb"
elif [ -n "$deviceinfo_dtb" ]; then
    DTB="$KERNEL_OUT/../$deviceinfo_codename.dtb"
    PREFIX=$KERNEL_OUT/arch/$ARCH/boot/dts/
    DTBS="$PREFIX${deviceinfo_dtb// / $PREFIX}"
    cat $DTBS > $DTB
fi

if [ -n "$deviceinfo_prebuilt_dtbo" ]; then
    DTBO="$HERE/$deviceinfo_prebuilt_dtbo"
elif [ -n "$deviceinfo_dtbo" ]; then
    DTBO="$(dirname "$OUT")/dtbo.img"
fi

if [ -n "$deviceinfo_recovery_dtbo" ]; then
    RECOVERY_DTBO="$HERE/$deviceinfo_recovery_dtbo"
else
    RECOVERY_DTBO="$DTBO"
fi

if [ "$deviceinfo_bootimg_header_version" -eq 2 ]; then
    mkbootimg --kernel "$KERNEL" --ramdisk "$RAMDISK" --dtb "$DTB" --base $deviceinfo_flash_offset_base --kernel_offset $deviceinfo_flash_offset_kernel --ramdisk_offset $deviceinfo_flash_offset_ramdisk --second_offset $deviceinfo_flash_offset_second --tags_offset $deviceinfo_flash_offset_tags --dtb_offset $deviceinfo_flash_offset_dtb --pagesize $deviceinfo_flash_pagesize --cmdline "$deviceinfo_kernel_cmdline" -o "$OUT" --header_version $deviceinfo_bootimg_header_version --os_version $deviceinfo_bootimg_os_version --os_patch_level $deviceinfo_bootimg_os_patch_level
else
    mkbootimg --kernel "$KERNEL" --ramdisk "$RAMDISK" --base $deviceinfo_flash_offset_base --kernel_offset $deviceinfo_flash_offset_kernel --ramdisk_offset $deviceinfo_flash_offset_ramdisk --second_offset $deviceinfo_flash_offset_second --tags_offset $deviceinfo_flash_offset_tags --pagesize $deviceinfo_flash_pagesize --cmdline "$deviceinfo_kernel_cmdline" -o "$OUT"
fi

if [ -n "$deviceinfo_bootimg_append_vbmeta" ] && $deviceinfo_bootimg_append_vbmeta; then
    python2 "$TMPDOWN/avb/avbtool" append_vbmeta_image --image "$OUT" --partition_size "$deviceinfo_bootimg_partition_size" --vbmeta_image "$TMPDOWN/vbmeta.img"
fi

    if [ "$deviceinfo_bootimg_header_version" -eq 2 ]; then
        EXTRA_ARGS+=" --header_version $deviceinfo_bootimg_header_version --dtb $DTB --dtb_offset $deviceinfo_flash_offset_dtb"
    fi

    if [ -n "$RECOVERY_DTBO" ]; then
        EXTRA_ARGS+=" --recovery_dtbo $RECOVERY_DTBO"
    fi

if [ -n "$deviceinfo_has_recovery_partition" ] && $deviceinfo_has_recovery_partition; then
    RECOVERY="$(dirname "$OUT")/recovery.img"
    RECOVERY_RAMDISK="$HERE/ramdisk-recovery.img"
    EXTRA_ARGS=""
    mkbootimg --kernel "$KERNEL" --ramdisk "$RECOVERY_RAMDISK" --dtb "$DTB" --base $deviceinfo_flash_offset_base --kernel_offset $deviceinfo_flash_offset_kernel --ramdisk_offset $deviceinfo_flash_offset_ramdisk --second_offset $deviceinfo_flash_offset_second --tags_offset $deviceinfo_flash_offset_tags --dtb_offset $deviceinfo_flash_offset_dtb --pagesize $deviceinfo_flash_pagesize --cmdline "$deviceinfo_kernel_cmdline" -o "$RECOVERY" --os_version $deviceinfo_bootimg_os_version --os_patch_level $deviceinfo_bootimg_os_patch_level --header_version $deviceinfo_bootimg_header_version $EXTRA_ARGS
  fi

if [ -n "$deviceinfo_recovery_partition_size" ]; then
        python2 "$TMPDOWN/avb/avbtool" add_hash_footer --image "$RECOVERY" --partition_name recovery --partition_size $deviceinfo_recovery_partition_size
fi

if [ -n "$deviceinfo_dtbo_partition_size" ] && [ -f "$DTBO" ]; then
    python2 "$TMPDOWN/avb/avbtool" add_hash_footer --image "$DTBO" --partition_name dtbo --partition_size $deviceinfo_dtbo_partition_size
fi
