TARGET = iphone:clang:latest:14.0
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TikTokCapture

TikTokCapture_FILES = Tweak.x
TikTokCapture_CFLAGS = -fobjc-arc
TikTokCapture_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
