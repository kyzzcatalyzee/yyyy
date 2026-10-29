TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DepthWall
DepthWall_FILES = Tweak.xm
DepthWall_CFLAGS = -fobjc-arc
DepthWall_FRAMEWORKS = UIKit Vision CoreImage CoreVideo CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk
