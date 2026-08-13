# Application.mk — Walkman Audio Effects HAL port
# Build config for NDK standalone + AOSP (mmm) consumption.

# OnePlus 3 (msm8996) je 64-bit primárně; 32-bit kompat pro legacy HAL.
APP_ABI := arm64-v8a armeabi-v7a
APP_PLATFORM := android-29      # Android 11 minimální
APP_STL := c++_static
APP_CPPFLAGS := -std=c++17 -Wall -Werror=return-type
APP_LDFLAGS := -Wl,--build-id

# Pro standalone NDK build (ndk-build), volí se jen APP_ABI/PLATFORM.
# Pro AOSP mmm: Application.mk je ignorováno; ABI řídí target/board config.
