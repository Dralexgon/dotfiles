cmake_minimum_required(VERSION 3.27)
project(cursortrail DESCRIPTION "Mouse pointer trail for Hyprland" VERSION 1.0)

set(CMAKE_CXX_STANDARD 23)

add_library(cursortrail SHARED main.cpp)

find_package(PkgConfig REQUIRED)
pkg_check_modules(deps REQUIRED IMPORTED_TARGET hyprland libdrm libinput libudev pixman-1 wayland-server xkbcommon)
target_link_libraries(cursortrail PRIVATE rt PkgConfig::deps)

install(TARGETS cursortrail)
