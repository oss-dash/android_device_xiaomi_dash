# SPDX-License-Identifier: Apache-2.0
#
# Kernel built from source.
#
# The kernel source is Content-Creation-Club/android_kernel_xiaomi_dash, synced
# to kernel/xiaomi/dash/kernel-6.6 by the local manifest. Build it with
#
#   device/xiaomi/dash/kernel/build-kernel.sh
#
# which stages the image, the uapi headers, the dtb and the modules into
# kernel/xiaomi/dash/out, in the same layout as the prebuilt kernel.
#
# BoardConfig.mk only includes this file when the kernel was built from source;
# the module lists are shared with the prebuilt path there.

# Where the build script stages the kernel.
KERNEL_PATH := $(TOP)/kernel/xiaomi/dash/out

TARGET_PREBUILT_KERNEL := $(KERNEL_PATH)/$(BOARD_KERNEL_IMAGE_NAME)
TARGET_PREBUILT_KERNEL_HEADERS := $(KERNEL_PATH)/kernel-uapi-headers.tar.gz
BOARD_PREBUILT_DTBIMAGE_DIR := $(KERNEL_PATH)/dtb

# Fail loudly on an incomplete staged output instead of shipping a ROM
# without a camera, a video encoder, a wifi driver or a dtb.
MODULES_DIRS := vendor_dlkm vendor_ramdisk
$(foreach d,$(MODULES_DIRS),\
  $(if $(wildcard $(KERNEL_PATH)/modules/$d/*.ko),,$(error Missing $(KERNEL_PATH)/modules/$d/*.ko. Run device/xiaomi/dash/kernel/build-kernel.sh))\
  $(if $(wildcard $(KERNEL_PATH)/modules/$d/modules.load),,$(error Missing $(KERNEL_PATH)/modules/$d/modules.load. Run device/xiaomi/dash/kernel/build-kernel.sh)))
$(if $(wildcard $(KERNEL_PATH)/modules/vendor_ramdisk/modules.load.recovery),,$(error Missing $(KERNEL_PATH)/modules/vendor_ramdisk/modules.load.recovery. Run device/xiaomi/dash/kernel/build-kernel.sh))
$(if $(wildcard $(KERNEL_PATH)/dtb/*.dtb),,$(if $(wildcard $(KERNEL_PATH)/dtb/dtb.img),,$(error Missing a dtb in $(KERNEL_PATH)/dtb. Run device/xiaomi/dash/kernel/build-kernel.sh)))

# The deployment list of the source build mirrors the kleaf build of the
# device: the prebuilt lists plus the extra profiling, charger and
# wifi-variant drivers.
include $(DEVICE_PATH)/kernel/modules.mk
