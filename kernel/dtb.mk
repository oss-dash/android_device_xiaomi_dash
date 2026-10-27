# SPDX-License-Identifier: Apache-2.0
#
# The dtb the boot images carry. It is the xiaomi mt6991 board base with the
# dash overlay applied and wrapped in the 64-byte MTK LK header, the way the
# stock vendor_boot ships the dtb section.
#
# vendor/lineage/build/tasks/kernel.mk includes this file when
# BOARD_CUSTOM_DTBIMG_MK is set, so the dtb is built from the device modules
# sources as part of the ROM build, next to the kernel itself.
#
# The build forbids tools from PATH, so the pinned kernel clang preprocesses
# the sources and the host dtc/fdtoverlay binaries from external/dtc do the
# rest.

DASH_DEVMOD := $(TOP)/kernel/xiaomi/dash/device-modules
DASH_DTS := $(DASH_DEVMOD)/arch/arm64/boot/dts
DASH_DTB_INTERMEDIATES := $(call intermediates-dir-for,PACKAGING,dash_dtb)
DASH_DTB_BASE := $(DASH_DTB_INTERMEDIATES)/base.dtb
DASH_DTB_OVERLAY := $(DASH_DTB_INTERMEDIATES)/dash.dtbo
DASH_DTB_MERGED := $(DASH_DTB_INTERMEDIATES)/dash.dtb

DASH_CPP := $(TARGET_KERNEL_CLANG_PATH)/bin/clang
# The pinned clang keeps its runtime libraries in lib64; kernel.mk exports the
# same for its own rules.
DASH_CPP_ENV := LD_LIBRARY_PATH=$(TARGET_KERNEL_CLANG_PATH)/lib64:$$LD_LIBRARY_PATH
DASH_CPP_INC := -I$(DASH_DTS) -I$(DASH_DTS)/mediatek \
    -I$(DASH_DEVMOD)/include -I$(TOP)/kernel/xiaomi/dash/kernel-6.6/include
DASH_CPP_FLAGS := -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp
DASH_DTC := $(HOST_OUT_EXECUTABLES)/dtc
DASH_FDTOVERLAY := $(HOST_OUT_EXECUTABLES)/fdtoverlay
DASH_DTB_WRAPPER := $(DASH_DEVMOD)/scripts/mtk_dtb_header.py

$(DASH_DTB_BASE): $(DASH_DTS)/mediatek/xiaomi_mt6991_common.dts $(DASH_DTC)
	@mkdir -p $(dir $@)
	$(hide) $(DASH_CPP_ENV) $(DASH_CPP) $(DASH_CPP_FLAGS) $(DASH_CPP_INC) $< | $(DASH_DTC) -I dts -O dtb -@ -Wno-unit_address_vs_reg -o $@ -

$(DASH_DTB_OVERLAY): $(DASH_DTS)/mediatek/dash.dts $(DASH_DTC)
	@mkdir -p $(dir $@)
	$(hide) $(DASH_CPP_ENV) $(DASH_CPP) $(DASH_CPP_FLAGS) $(DASH_CPP_INC) $< | $(DASH_DTC) -I dts -O dtb -@ -Wno-unit_address_vs_reg -o $@ -

$(DASH_DTB_MERGED): $(DASH_DTB_BASE) $(DASH_DTB_OVERLAY) $(DASH_FDTOVERLAY)
	$(hide) $(DASH_FDTOVERLAY) -i $(DASH_DTB_BASE) -o $@ $(DASH_DTB_OVERLAY)
	$(hide) python3 $(DASH_DTB_WRAPPER) $@

$(INSTALLED_DTBIMAGE_TARGET): $(DASH_DTB_MERGED)
	$(hide) cp -f $< $@
