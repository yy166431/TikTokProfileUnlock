TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = TikTok Aweme

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TikTokProfileUnlock

TikTokProfileUnlock_FILES = Tweak_simple.x
TikTokProfileUnlock_CFLAGS = -fobjc-arc
TikTokProfileUnlock_FRAMEWORKS = UIKit Foundation CFNetwork
TikTokProfileUnlock_PRIVATE_FRAMEWORKS =
TikTokProfileUnlock_LDFLAGS = -undefined dynamic_lookup
TikTokProfileUnlock_LIBRARIES = z

include $(THEOS)/makefiles/tweak.mk
