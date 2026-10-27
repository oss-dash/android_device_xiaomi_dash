#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/xiaomi/dash

# A/B
AB_OTA_UPDATER := true
AB_OTA_PARTITIONS := \
    boot \
    init_boot \
    odm \
    odm_dlkm \
    product \
    pvmfw \
    system \
    system_dlkm \
    system_ext \
    vbmeta \
    vbmeta_system \
    vbmeta_vendor \
    vendor \
    vendor_boot \
    vendor_dlkm

# Architecture
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_VARIANT := generic
TARGET_CPU_VARIANT_RUNTIME := cortex-a55

# Bootloader
TARGET_BOOTLOADER_BOARD_NAME := dash
TARGET_NO_BOOTLOADER := true

# Display
TARGET_SCREEN_DENSITY := 504
TARGET_USES_VULKAN := true

# Kernel
ifeq ($(TARGET_BUILD_VARIANT),eng)
BOARD_BOOTCONFIG += androidboot.selinux=permissive
endif

# Boot image (header v4, the kernel image is lz4 compressed)
BOARD_BOOT_HEADER_VERSION := 4
BOARD_KERNEL_BASE := 0x7fff8000
BOARD_KERNEL_OFFSET := 0x00008000
BOARD_KERNEL_PAGESIZE := 4096
BOARD_TAGS_OFFSET := 0x07c88000
BOARD_RAMDISK_OFFSET := 0x26f08000
BOARD_RAMDISK_USE_LZ4 := true

BOARD_BOOTCONFIG += androidboot.console=0
BOARD_BOOTCONFIG += androidboot.hypervisor.version=GenieZone
BOARD_BOOTCONFIG += androidboot.hypervisor.vm.supported=1
BOARD_BOOTCONFIG += androidboot.hypervisor.protected_vm.supported=1
BOARD_KERNEL_CMDLINE += bootopt=64S3,32N2,64N2
BOARD_KERNEL_CMDLINE += kasan=off
BOARD_KERNEL_CMDLINE += rcupdate.rcu_expedited=1 rcutree.enable_rcu_lazy

BOARD_INIT_BOOT_HEADER_VERSION := 4

BOARD_MKBOOTIMG_ARGS += \
    --base $(BOARD_KERNEL_BASE) \
    --dtb_offset $(BOARD_TAGS_OFFSET) \
    --header_version $(BOARD_BOOT_HEADER_VERSION) \
    --kernel_offset $(BOARD_KERNEL_OFFSET) \
    --pagesize $(BOARD_KERNEL_PAGESIZE) \
    --ramdisk_offset $(BOARD_RAMDISK_OFFSET) \
    --tags_offset $(BOARD_TAGS_OFFSET)

BOARD_MKBOOTIMG_INIT_ARGS += \
    --header_version $(BOARD_INIT_BOOT_HEADER_VERSION)

BOARD_USES_GENERIC_KERNEL_IMAGE := true
BOARD_INCLUDE_DTB_IN_BOOTIMG := true

# The kernel is compiled as part of the ROM build by
# vendor/lineage/build/tasks/kernel.mk: gki_defconfig is the GKI base,
# mgk_64_k66_defconfig the MT6991 platform config and dash.config the dash
# device config. The mtk device modules are an external module tree next to
# the kernel source, the same layout the Kleaf build uses.
TARGET_NO_KERNEL := false
TARGET_KERNEL_SOURCE := kernel/xiaomi/dash/kernel-6.6
TARGET_KERNEL_ARCH := arm64
TARGET_KERNEL_HEADER_ARCH := arm64
TARGET_KERNEL_CONFIG := gki_defconfig
TARGET_KERNEL_CONFIG_EXT := \
    kernel/xiaomi/dash/device-modules/kernel/configs/mgk_64_k66.config \
    kernel/xiaomi/dash/device-modules/kernel/configs/dash.config
# Absolute paths: the module makefiles use DEVICE_MODULES_PATH in -I flags
# and includes, and kbuild runs them from the object directory, so a relative
# path (./kernel/...) resolves against the wrong root and every header the
# device modules provide is lost.
# KCFLAGS is what build.config.common exports for the MTK kernel build; the
# Mali compat header keys off __ANDROID_COMMON_KERNEL__ and the two warnings
# are errors on this tree otherwise.
TARGET_KERNEL_ADDITIONAL_FLAGS := \
    KCFLAGS='-D__ANDROID_COMMON_KERNEL__ -Wno-error=enum-compare -Wno-error=sometimes-uninitialized' \
    ROOT_DIR=$(abspath $(TOP)/kernel/xiaomi/dash) \
    KERNEL_DIR=$(abspath $(TOP)/kernel/xiaomi/dash/kernel-6.6) \
    DEVICE_MODULES_DIR=device-modules \
    DEVICE_MODULES_REL_DIR=../device-modules \
    KCONFIG_EXT_PREFIX=../device-modules/ \
    DEVICE_MODULES_PATH=$(abspath $(TOP)/kernel/xiaomi/dash/device-modules) \
    DEVCIE_MODULES_INCLUDE=-I$(abspath $(TOP)/kernel/xiaomi/dash/device-modules)/include
TARGET_KERNEL_VERSION := 6.6
TARGET_KERNEL_CLANG_VERSION := r510928
BOARD_KERNEL_IMAGE_NAME := Image.lz4

# The dtb is the xiaomi board base with the dash overlay applied, wrapped in
# the MTK LK header: built from the device modules sources by this file.
BOARD_CUSTOM_DTBIMG_MK := $(DEVICE_PATH)/kernel/dtb.mk

# Out-of-tree module trees, relative to the kernel source directory.
TARGET_KERNEL_EXT_MODULE_ROOT := kernel/xiaomi/dash
TARGET_KERNEL_EXT_MODULES := \
    device-modules \
    vendor/mediatek/kernel_modules/connectivity/common \
    vendor/mediatek/kernel_modules/connectivity/conninfra \
    vendor/mediatek/kernel_modules/connectivity/connfem \
    vendor/mediatek/kernel_modules/connectivity/gps/gps_stp \
    vendor/mediatek/kernel_modules/connectivity/gps/data_link \
    vendor/mediatek/kernel_modules/connectivity/gps/gps_pwr \
    vendor/mediatek/kernel_modules/connectivity/gps/mi_gps_pwr \
    vendor/mediatek/kernel_modules/connectivity/gps/gps_scp \
    vendor/mediatek/kernel_modules/connectivity/fmradio \
    vendor/mediatek/kernel_modules/connectivity/wlan/adaptor \
    vendor/mediatek/kernel_modules/connectivity/wlan/adaptor/wlan_page_pool \
    vendor/mediatek/kernel_modules/connectivity/wlan/core/gen4m/build/connac3x/6991_6639_new9gen2 \
    vendor/mediatek/kernel_modules/connectivity/wlan/core/gen4m/build/connac3x/6991_6653 \
    vendor/mediatek/kernel_modules/connectivity/bt/linux_v2 \
    vendor/mediatek/kernel_modules/gpu \
    vendor/mediatek/kernel_modules/hbt_driver_cus \
    vendor/mediatek/kernel_modules/mtkcam \
    vendor/mediatek/kernel_modules/afs_common_utils \
    vendor/mediatek/kernel_modules/afs_core_cus \
    vendor/mediatek/kernel_modules/fpsgo_cus \
    vendor/mediatek/kernel_modules/sched_cus \
    vendor/mediatek/kernel_modules/met_drv_v3 \
    vendor/mediatek/kernel_modules/met_drv_v3/met_api \
    vendor/mediatek/kernel_modules/task_turbo_cus \
    vendor/mediatek/kernel_modules/game_cus

# Module load lists taken from the stock kernel. kernel.mk installs the built
# modules into the partitions and writes these lists into the images.
# SYSTEM_KERNEL_MODULES names the modules of system_dlkm, everything else goes
# to vendor_dlkm.
#
# Two lists are not verbatim copies of the stock ones:
#  - bluetooth.ko is listed in both stock lists, system_dlkm and vendor_dlkm.
#    kernel.mk gives a module exactly one partition, and the GKI copy in
#    system_dlkm is the one that loads, so the vendor_dlkm list omits it.
#  - macsec.ko is an unused wired-Ethernet module. kernel.mk picks the
#    vendor_dlkm set by substring-matching every module name against
#    SYSTEM_KERNEL_MODULES, so "sec.ko" matches inside "macsec.ko" and the
#    MediaTek sec module would never reach vendor_dlkm. macsec is therefore
#    left out of the system_dlkm list; it is built into vendor_dlkm instead
#    (and not loaded) so sec.ko stays where the stock kernel loads it from.
#
# metis, mi_schedule and xr_qs are not in the vendor_dlkm list because they do
# not build: metis is not wired into the device-modules Makefile yet, and the
# other two patch scheduler internals that 6.6 does not have.
SYSTEM_KERNEL_MODULES := $(shell cat $(DEVICE_PATH)/kernel/modules.load.system)
BOARD_SYSTEM_KERNEL_MODULES_LOAD := $(shell cat $(DEVICE_PATH)/kernel/modules.load.system)
BOARD_VENDOR_KERNEL_MODULES_LOAD := $(shell cat $(DEVICE_PATH)/kernel/modules.load.vendor_dlkm)
# The ramdisk ships the whole stock module set (ccci, ccmni, mddp, the
# rebooter, mediatek-drm and the mtk mailboxes among them), not only the
# modules the platform list auto loads.
BOOT_KERNEL_MODULES := $(shell cat $(DEVICE_PATH)/kernel/modules.list.vendor_ramdisk)
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD := $(shell cat $(DEVICE_PATH)/kernel/modules.load.platform)

# Partitions
BOARD_USES_METADATA_PARTITION := true

BOARD_BOOTIMAGE_PARTITION_SIZE := 67108864
BOARD_DTBOIMG_PARTITION_SIZE := 8388608
BOARD_FLASH_BLOCK_SIZE := $(BOARD_KERNEL_PAGESIZE)
BOARD_INIT_BOOT_IMAGE_PARTITION_SIZE := $(BOARD_DTBOIMG_PARTITION_SIZE)
BOARD_PVMFWIMAGE_PARTITION_SIZE := 20971520
BOARD_VENDOR_BOOTIMAGE_PARTITION_SIZE := 67108864

ifeq ($(PRODUCT_SYSTEM_PARTITIONS_FILE_SYSTEM_TYPE),ext4)
-include vendor/lineage/config/BoardConfigReservedSize.mk
endif

BOARD_SUPER_PARTITION_SIZE := 9126805504
BOARD_SUPER_PARTITION_GROUPS := xiaomi_dynamic_partitions
BOARD_XIAOMI_DYNAMIC_PARTITIONS_PARTITION_LIST := system product system_ext vendor odm system_dlkm vendor_dlkm odm_dlkm
BOARD_XIAOMI_DYNAMIC_PARTITIONS_SIZE := $(shell expr $(BOARD_SUPER_PARTITION_SIZE) - 4194304)

BOARD_PRODUCTIMAGE_FILE_SYSTEM_TYPE := $(PRODUCT_SYSTEM_PARTITIONS_FILE_SYSTEM_TYPE)
BOARD_SYSTEMIMAGE_FILE_SYSTEM_TYPE := $(PRODUCT_SYSTEM_PARTITIONS_FILE_SYSTEM_TYPE)
BOARD_SYSTEM_EXTIMAGE_FILE_SYSTEM_TYPE := $(PRODUCT_SYSTEM_PARTITIONS_FILE_SYSTEM_TYPE)
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_ODMIMAGE_FILE_SYSTEM_TYPE := erofs
# system_dlkm carries the core GKI modules (rfkill, bluetooth, hci_uart):
# without the partition cfg80211 and bluetooth cannot load.
BOARD_SYSTEM_DLKMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := erofs
BOARD_ODM_DLKMIMAGE_FILE_SYSTEM_TYPE := erofs

BOARD_EROFS_COMPRESS_HINTS := $(DEVICE_PATH)/configs/partitions/erofs_compress_hints.txt
BOARD_EROFS_PCLUSTER_SIZE := 262144
PRODUCT_FS_COMPRESSION := 1

TARGET_COPY_OUT_ODM := odm
TARGET_COPY_OUT_ODM_DLKM := odm_dlkm
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_SYSTEM_DLKM := system_dlkm
TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_VENDOR_DLKM := vendor_dlkm

# Recovery
BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true
BOARD_INCLUDE_RECOVERY_RAMDISK_IN_VENDOR_BOOT := true
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/init/fstab.mt6991
TARGET_RECOVERY_PIXEL_FORMAT := RGBX_8888
TARGET_USERIMAGES_USE_F2FS := true

# SEPolicy
include device/lineage/sepolicy/libion/sepolicy.mk
include device/mediatek/sepolicy_vndr/SEPolicy.mk
BOARD_VENDOR_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor
SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/private
SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/public

# Verified Boot
BOARD_AVB_ENABLE := true
BOARD_MOVE_GSI_AVB_KEYS_TO_VENDOR_BOOT := true
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 1

BOARD_AVB_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem
BOARD_AVB_ALGORITHM := SHA256_RSA4096
BOARD_AVB_ROLLBACK_INDEX_LOCATION := 0

BOARD_AVB_BOOT_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem
BOARD_AVB_BOOT_ALGORITHM := SHA256_RSA4096
BOARD_AVB_BOOT_ROLLBACK_INDEX := $(PLATFORM_SECURITY_PATCH_TIMESTAMP)
BOARD_AVB_BOOT_ROLLBACK_INDEX_LOCATION := 3

BOARD_AVB_VBMETA_SYSTEM := product pvmfw system system_ext system_dlkm
BOARD_AVB_VBMETA_SYSTEM_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem
BOARD_AVB_VBMETA_SYSTEM_ALGORITHM := SHA256_RSA4096
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX := $(PLATFORM_SECURITY_PATCH_TIMESTAMP)
BOARD_AVB_VBMETA_SYSTEM_ROLLBACK_INDEX_LOCATION := 2

BOARD_AVB_VBMETA_VENDOR := odm odm_dlkm vendor vendor_dlkm
BOARD_AVB_VBMETA_VENDOR_KEY_PATH := external/avb/test/data/testkey_rsa4096.pem
BOARD_AVB_VBMETA_VENDOR_ALGORITHM := SHA256_RSA4096
BOARD_AVB_VBMETA_VENDOR_ROLLBACK_INDEX := $(PLATFORM_SECURITY_PATCH_TIMESTAMP)
BOARD_AVB_VBMETA_VENDOR_ROLLBACK_INDEX_LOCATION := 4

BOARD_AVB_ODM_ADD_HASHTREE_FOOTER_ARGS += --hash_algorithm sha256
BOARD_AVB_ODM_DLKM_ADD_HASHTREE_FOOTER_ARGS += --hash_algorithm sha256
BOARD_AVB_PRODUCT_ADD_HASHTREE_FOOTER_ARGS += --hash_algorithm sha256
BOARD_AVB_SYSTEM_ADD_HASHTREE_FOOTER_ARGS += --hash_algorithm sha256
BOARD_AVB_SYSTEM_EXT_ADD_HASHTREE_FOOTER_ARGS += --hash_algorithm sha256
BOARD_AVB_VENDOR_ADD_HASHTREE_FOOTER_ARGS += --hash_algorithm sha256
BOARD_AVB_VENDOR_DLKM_ADD_HASHTREE_FOOTER_ARGS += --hash_algorithm sha256

# VINTF
DEVICE_FRAMEWORK_COMPATIBILITY_MATRIX_FILE += \
    $(DEVICE_PATH)/compatibility_matrix.device.xml \
    device/xiaomi/dash-miuicamera/compatibility_matrix.camera.xml \
    hardware/mediatek/vintf/mediatek_framework_compatibility_matrix_aidl.xml \
    hardware/xiaomi/vintf/xiaomi_framework_compatibility_matrix.xml \
    $(DEVICE_PATH)/device_framework_matrix.xml
DEVICE_MANIFEST_FILE += $(DEVICE_PATH)/manifest.xml
DEVICE_MATRIX_FILE += $(DEVICE_PATH)/compatibility_matrix.xml

# Wifi
WPA_SUPPLICANT_VERSION := VER_0_8_X
BOARD_WPA_SUPPLICANT_DRIVER := NL80211
BOARD_HOSTAPD_DRIVER := $(BOARD_WPA_SUPPLICANT_DRIVER)
WIFI_DRIVER_FW_PATH_PARAM := "/dev/wmtWifi"
WIFI_DRIVER_FW_PATH_STA := "STA"
WIFI_DRIVER_FW_PATH_AP := "AP"
WIFI_DRIVER_FW_PATH_P2P := "P2P"
WIFI_DRIVER_STATE_CTRL_PARAM := $(WIFI_DRIVER_FW_PATH_PARAM)
WIFI_DRIVER_STATE_ON := "1"
WIFI_DRIVER_STATE_OFF := "0"
WIFI_HAL_INTERFACE_COMBINATIONS := {{{STA}, 2}}
WIFI_HAL_INTERFACE_COMBINATIONS += ,{{{AP_BRIDGED}, 1},}
WIFI_HAL_INTERFACE_COMBINATIONS += ,{{{STA}, 1}, {{AP}, 1}}
WIFI_HAL_INTERFACE_COMBINATIONS += ,{{{STA}, 1}, {{P2P}, 1}}
WIFI_HAL_INTERFACE_COMBINATIONS += ,{{{STA}, 1}, {{NAN}, 1}}
WIFI_HIDL_UNIFIED_SUPPLICANT_SERVICE_RC_ENTRY := true
WIFI_FEATURE_HOSTAPD_11AX := true
WIFI_FEATURE_SUPPLICANT_11AX := true

# Inherit the proprietary files
include vendor/xiaomi/dash/BoardConfigVendor.mk
-include device/xiaomi/dash-miuicamera/BoardConfig.mk
