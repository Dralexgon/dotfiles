cmake_minimum_required(VERSION 3.27)
project(windowfx DESCRIPTION "Closing and opening window animations (petals, blood) for Hyprland" VERSION 1.1)

set(CMAKE_CXX_STANDARD 23)

add_library(windowfx SHARED main.cpp)

find_package(PkgConfig REQUIRED)
pkg_check_modules(deps REQUIRED IMPORTED_TARGET hyprland libdrm libinput libudev pixman-1 wayland-server xkbcommon)
target_link_libraries(windowfx PRIVATE rt PkgConfig::deps)

install(TARGETS windowfx)
