# SPDX-License-Identifier: Apache-2.0
#
# Boot DTB: the xiaomi mt6991 board base, matching the stock vendor_boot DTB.
#
# Stock carries mbox-attr on four mailbox users. Without it the mtk mailbox
# driver keeps IRQF_NO_SUSPEND and enable_irq_wake() fires the "misconfigured
# IRQ" detector. Apply the same four properties here.
#
# The dash board overlay is applied by the stock dtbo partition, so do not
# merge it. The build places this image in vendor_boot, which expects the
# 64-byte MTK LK header followed by the FDT; wrap it last.

DASH_DEVMOD := $(TOP)/kernel/xiaomi/dash/device-modules
DASH_DTS := $(DASH_DEVMOD)/arch/arm64/boot/dts
DASH_DTB_INTERMEDIATES := $(call intermediates-dir-for,PACKAGING,dash_dtb)
DASH_DTB_RAW := $(DASH_DTB_INTERMEDIATES)/base.dtb
DASH_DTB := $(DASH_DTB_INTERMEDIATES)/dash.dtb

DASH_CPP := $(TARGET_KERNEL_CLANG_PATH)/bin/clang
DASH_CPP_ENV := LD_LIBRARY_PATH=$(TARGET_KERNEL_CLANG_PATH)/lib64:$$LD_LIBRARY_PATH
DASH_CPP_INC := -I$(DASH_DTS) -I$(DASH_DTS)/mediatek \
    -I$(DASH_DEVMOD)/include -I$(TOP)/kernel/xiaomi/dash/kernel-6.6/include
DASH_CPP_FLAGS := -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp
DASH_DTC := $(HOST_OUT_EXECUTABLES)/dtc
DASH_FDTPUT := $(HOST_OUT_EXECUTABLES)/fdtput
DASH_DTB_WRAPPER := $(DASH_DEVMOD)/scripts/mtk_dtb_header.py

$(DASH_DTB_RAW): $(DASH_DTS)/mediatek/xiaomi_mt6991_common.dts $(DASH_DTC)
	@mkdir -p $(dir $@)
	$(hide) $(DASH_CPP_ENV) $(DASH_CPP) $(DASH_CPP_FLAGS) $(DASH_CPP_INC) $< | $(DASH_DTC) -I dts -O dtb -@ -Wno-unit_address_vs_reg -o $@ -

$(DASH_DTB): $(DASH_DTB_RAW) $(DASH_FDTPUT) $(DASH_DTB_WRAPPER)
	$(hide) cp -f $< $@
	$(hide) $(DASH_FDTPUT) -t x $@ /soc/gpueb@4b000000 mbox-attr 0
	$(hide) $(DASH_FDTPUT) -t x $@ /scp@1c800000 mbox-attr 0 0 0 0 0 0
	$(hide) $(DASH_FDTPUT) -t x $@ /vcp@31800000 mbox-attr 0 0 0
	$(hide) $(DASH_FDTPUT) -t x $@ /mmup@31a00000 mbox-attr 0 0
	$(hide) python3 $(DASH_DTB_WRAPPER) $@

$(INSTALLED_DTBIMAGE_TARGET): $(DASH_DTB)
	$(hide) cp -f $< $@
