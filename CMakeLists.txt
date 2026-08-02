cmake_minimum_required(VERSION 4.2.0)
project(fontconfig LANGUAGES C)

find_package(EXPAT REQUIRED)
find_package(Freetype REQUIRED)

add_library(fontconfig SHARED
  src/fcinit.c
  src/fccfg.c
  src/fcdefault.c
  src/fcpat.c
  src/fcmatch.c)
target_link_libraries(fontconfig PRIVATE
  EXPAT::EXPAT
  Freetype::Freetype)
