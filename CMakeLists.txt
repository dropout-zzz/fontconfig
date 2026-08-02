cmake_minimum_required(VERSION 4.2.0)
project(fontconfig LANGUAGES C)

find_package(EXPAT REQUIRED)
find_package(Freetype REQUIRED)

###
set(DOT_GEN_H ${CMAKE_CURRENT_BINARY_DIR}/dot_gen_h)

configure_file(src/fcstdint.h.in ${DOT_GEN_H}/fcstdint.h COPYONLY)

add_custom_target(dropout_generated_headers DEPENDS
  ${DOT_GEN_H}/fcstdint.h)
###

add_library(fontconfig SHARED
  src/fcinit.c
  src/fccfg.c
  src/fcdefault.c
  src/fcpat.c
  src/fcmatch.c)
add_dependencies(fontconfig
  dropout_generated_headers)
target_include_directories(fontconfig PRIVATE
  ${DOT_GEN_H})
target_link_libraries(fontconfig PRIVATE
  EXPAT::EXPAT
  Freetype::Freetype)
