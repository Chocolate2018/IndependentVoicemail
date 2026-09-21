TARGET := iphone:clang:latest:16.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = IndependentVoicemail

IndependentVoicemail_FILES = Tweak.xm
IndependentVoicemail_CFLAGS = -fobjc-arc
IndependentVoicemail_FRAMEWORKS = UIKit AVFoundation Foundation CallKit

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard || true"
