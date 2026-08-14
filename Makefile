TARGET = iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TikTokCapture

TikTokCapture_FILES = Tweak.x
TikTokCapture_CFLAGS = -fobjc-arc
TikTokCapture_FRAMEWORKS = UIKit Foundation
TikTokCapture_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

after-stage::
	@echo "==== Dylib only build ===="
	@mkdir -p $(THEOS_STAGING_DIR)/TrollStore
	@cp $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/TikTokCapture.dylib $(THEOS_STAGING_DIR)/TrollStore/
	@cp $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/TikTokCapture.plist $(THEOS_STAGING_DIR)/TrollStore/
	@echo "✓ Dylib ready in .theos/_/TrollStore/"
