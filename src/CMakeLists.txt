# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(grades_native_fibonacci_library VERSION 0.0.1 LANGUAGES C)

add_library(grades_native_fibonacci SHARED
  "grades_native_fibonacci.c"
)

set_target_properties(grades_native_fibonacci PROPERTIES
  PUBLIC_HEADER grades_native_fibonacci.h
  OUTPUT_NAME "grades_native_fibonacci"
)

target_compile_definitions(grades_native_fibonacci PUBLIC DART_SHARED_LIB)
