cmake_minimum_required(VERSION 3.27)
project(cursorfx DESCRIPTION "Petals, blood or images behind the mouse pointer for Hyprland" VERSION 1.0)

set(CMAKE_CXX_STANDARD 23)

add_library(cursorfx SHARED main.cpp)

find_package(PkgConfig REQUIRED)
pkg_check_modules(deps REQUIRED IMPORTED_TARGET hyprland libdrm libinput libudev pixman-1 wayland-server xkbcommon cairo)
target_link_libraries(cursorfx PRIVATE rt PkgConfig::deps)

install(TARGETS cursorfx)
