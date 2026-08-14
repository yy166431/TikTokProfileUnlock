TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TikTokHeadersCapture

TikTokHeadersCapture_FILES = Tweak.x
TikTokHeadersCapture_CFLAGS = -fobjc-arc
TikTokHeadersCapture_FRAMEWORKS = UIKit Foundation
TikTokHeadersCapture_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
