TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TikTokMITMProxy

TikTokMITMProxy_FILES = Tweak_MITM.x
TikTokMITMProxy_CFLAGS = -fobjc-arc
TikTokMITMProxy_FRAMEWORKS = UIKit Foundation Security CFNetwork
TikTokMITMProxy_LDFLAGS = -undefined dynamic_lookup
TikTokMITMProxy_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	@echo "==== Dylib only build ===="
	@mkdir -p $(THEOS_STAGING_DIR)/TrollStore
	@cp $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/TikTokCapture.dylib $(THEOS_STAGING_DIR)/TrollStore/
	@cp $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/TikTokCapture.plist $(THEOS_STAGING_DIR)/TrollStore/
	@echo "✓ Dylib ready in .theos/_/TrollStore/"
