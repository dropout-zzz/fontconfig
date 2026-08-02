cmake_minimum_required(VERSION 4.2.0)
project(fontconfig LANGUAGES C)

# we need for generating headers
find_package(Python3 COMPONENTS Interpreter REQUIRED)

find_package(EXPAT REQUIRED)
find_package(Freetype REQUIRED)

###
set(DOT_GEN_H ${CMAKE_CURRENT_BINARY_DIR}/dot_gen_h)

configure_file(src/fcstdint.h.in ${DOT_GEN_H}/fcstdint.h COPYONLY)
##
set(DOT_FC_H ${DOT_GEN_H}/fontconfig/fontconfig.h)

# variables needed by the header template
# sync these with configure.ac and meson.build!
set(CACHE_VERSION 12)
set(CACHE_SNAP_VERSION 0)
if(CACHE_SNAP_VERSION GREATER 0)
  math(EXPR NEXT_CACHE_VERSION "${CACHE_VERSION} + 1")
else()
  set(NEXT_CACHE_VERSION 0)
endif()

configure_file(fontconfig/fontconfig.h.in ${DOT_FC_H} @ONLY)
##
set(DOT_ALIAS_H
  ${DOT_GEN_H}/fcalias.h
  ${DOT_GEN_H}/fcaliastail.h)
set(DOT_SRC ${CMAKE_CURRENT_SOURCE_DIR}/src)
set(DOT_ALIAS_IN
  ${DOT_FC_H}
  ${DOT_SRC}/fcdeprecate.h
  ${CMAKE_CURRENT_SOURCE_DIR}/fontconfig/fcprivate.h)

add_custom_command(
  OUTPUT ${DOT_ALIAS_H}
  COMMAND ${CMAKE_COMMAND} -E make_directory ${DOT_GEN_H}
  COMMAND ${Python3_EXECUTABLE} ${DOT_SRC}/makealias.py ${DOT_SRC} ${DOT_ALIAS_H} ${DOT_ALIAS_IN}
  DEPENDS Python3::Interpreter ${DOT_SRC}/makealias.py ${DOT_ALIAS_IN}
)

add_custom_target(dropout_generated_headers DEPENDS
  ${DOT_GEN_H}/fcstdint.h
  ${DOT_FC_H}
  ${DOT_ALIAS_H})
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
