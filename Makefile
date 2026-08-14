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
	@echo "==== Preparing dylib for TrollStore ===="
	@mkdir -p $(THEOS_STAGING_DIR)/TrollStore
	@cp $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/TikTokMITMProxy.dylib $(THEOS_STAGING_DIR)/TrollStore/
	@cp $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/TikTokMITMProxy.plist $(THEOS_STAGING_DIR)/TrollStore/
	@echo "✓ Dylib ready: .theos/_/TrollStore/TikTokMITMProxy.dylib"
	@echo "✓ Plist ready: .theos/_/TrollStore/TikTokMITMProxy.plist"
	@echo ""
	@echo "📦 Usage:"
	@echo "  1. DEB install: Install the .deb with TrollStore (auto-inject to TikTok)"
	@echo "  2. Manual inject: Use TrollStore Injector with the .dylib file"

