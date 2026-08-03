cmake_minimum_required(VERSION 4.2.0)
# update version when changed.
project(fontconfig LANGUAGES C VERSION 2.18.2)

set(CMAKE_C_STANDARD 11)

include(GNUInstallDirs)

if(WIN32)
  set(CACHE{FC_CACHEDIR} HELP "Default font cache location" VALUE "LOCAL_APPDATA_FONTCONFIG_CACHE")
else()
  set(CACHE{FC_CACHEDIR} HELP "Default font cache location" VALUE "${CMAKE_INSTALL_FULL_LOCALSTATEDIR}/cache/${PROJECT_NAME}")
endif()
set(CACHE{FC_TEMPLATEDIR} HELP "Location of configuration templates" VALUE "${CMAKE_INSTALL_FULL_DATAROOTDIR}/fontconfig/conf.avail")
if(WIN32)
  set(CACHE{DFLT_FONT_DIRS} HELP "Default system font directories" VALUE "WINDOWSFONTDIR" "WINDOWSUSERFONTDIR")
elseif(APPLE)
  set(CACHE{DFLT_FONT_DIRS} HELP "Default system font directories" VALUE "/System/Library/Fonts" "/Library/Fonts" "~/Library/Fonts" "/System/Library/Assets" "/System/Library/AssetsV2")
elseif(ANDROID)
  set(CACHE{DFLT_FONT_DIRS} HELP "Default system font directories" VALUE "/system/fonts/" "/product/fonts/")
else()
  set(CACHE{DFLT_FONT_DIRS} HELP "Default system font directories" VALUE "/usr/share/fonts" "/usr/local/share/fonts")
endif()
set(CACHE{FC_BASECONFIGDIR} HELP "Default base configuration directory" VALUE "${CMAKE_INSTALL_FULL_SYSCONFDIR}/fonts")
set(CACHE{FC_CONFIGDIR} HELP "Default configuration directory" VALUE "${FC_BASECONFIGDIR}/conf.d")

find_program(GPERF_EXECUTABLE gperf REQUIRED)

# we need for generating headers
find_package(Python3 COMPONENTS Interpreter REQUIRED)

find_package(EXPAT REQUIRED)
find_package(Freetype REQUIRED)

set(DOT_TESTS ${CMAKE_CURRENT_SOURCE_DIR}/meson-cc-tests)
try_compile(CC_TEST_FAM SOURCES ${DOT_TESTS}/flexible-array-member-test.c)

include(CheckTypeSize)
check_type_size("void *" SIZEOF_VOID_P BUILTIN_TYPES_ONLY)

function(CHECK_C_TYPE_ALIGN DOT_C_TYPE DOT_RESVAR)
  try_run(${DOT_RESVAR}_CC_TEST ${DOT_RESVAR}_CC_COMPILES SOURCE_FROM_CONTENT cc-test.c "
    #include <stddef.h>
    #include <stdio.h>
    typedef struct { char x; ${DOT_C_TYPE} y; } foo;
    int main(void) { printf(\"%d\", (int)offsetof(foo, y)); return 0; }
  " RUN_OUTPUT_STDOUT_VARIABLE TEST_OUTPUT)

  if(NOT ${DOT_RESVAR}_CC_COMPILES)
    message(FATAL_ERROR "can't compile test to determine alignment of ${DOT_C_TYPE}")
  endif()

  if(NOT ${DOT_RESVAR}_CC_TEST EQUAL 0)
    message(FATAL_ERROR "can't complete test to determine alignment of ${DOT_C_TYPE}")
  endif()

  set(${DOT_RESVAR} "${TEST_OUTPUT}" PARENT_SCOPE)
endfunction()

CHECK_C_TYPE_ALIGN("void *" ALIGNOF_VOID_P)

include(CheckIncludeFile)

check_include_file("unistd.h" HAVE_UNISTD_H)
check_include_file("dirent.h" HAVE_DIRENT_H)

include(CheckSymbolExists)

check_symbol_exists(vasprintf_l "stdio.h;stdarg.h;xlocale.h" HAVE_VASPRINTF_L)
check_symbol_exists(_vsnprintf_l "stdio.h" HAVE__VSNPRINTF_L)
check_symbol_exists(vasprintf "stdio.h;stdarg.h" HAVE_VASPRINTF)
try_compile(HAVE_C99_VSNPRINTF SOURCES ${DOT_TESTS}/c99-vsnprint-test.c)
check_symbol_exists(vsnprintf "stdio.h;stdarg.h" HAVE_VSNPRINTF)

try_compile(HAVE_STDATOMIC_PRIMITIVES SOURCES ${DOT_TESTS}/stdatomic-primitives-test.c)
try_compile(HAVE_INTEL_ATOMIC_PRIMITIVES SOURCES ${DOT_TESTS}/intel-atomic-primitives-test.c)
try_compile(HAVE_SOLARIS_ATOMIC_OPS SOURCES ${DOT_TESTS}/solaris-atomic-operations.c)

execute_process(
  COMMAND ${GPERF_EXECUTABLE} -L ANSI-C
  INPUT_FILE ${DOT_TESTS}/gperf.txt
  OUTPUT_VARIABLE GPERF_TEST_SRC
  COMMAND_ERROR_IS_FATAL ANY
)

include(CheckCSourceCompiles)

foreach(GPERF_SIZE_T_IT size_t unsigned)
  check_c_source_compiles("
    #include <string.h>
    const char *in_word_set(const char *, ${GPERF_SIZE_T_IT});
    ${GPERF_TEST_SRC}
    int main(void) { return 0; }
  " GPERF_TEST_${GPERF_SIZE_T_IT})

  if(GPERF_TEST_${GPERF_SIZE_T_IT})
    set(GPERF_SIZE_T ${GPERF_SIZE_T_IT})
    break()
  endif()
endforeach()

if(NOT DEFINED GPERF_SIZE_T)
  message(FATAL_ERROR "can't determine type of gperf \"len\" parameter")
endif()

message(STATUS "gperf len type is ${GPERF_SIZE_T}")

###
set(DOT_GEN_H ${CMAKE_CURRENT_BINARY_DIR}/dot_gen_h)

list(JOIN DFLT_FONT_DIRS "</dir> <dir>" FC_DEFAULT_FONTS)
if(NOT FC_DEFAULT_FONTS STREQUAL "")
  string(PREPEND FC_DEFAULT_FONTS "<dir>")
  string(APPEND FC_DEFAULT_FONTS "</dir>")
endif()

configure_file(dot-config.h.in ${DOT_GEN_H}/config.h)
###
foreach(STDINT_TYPE uint64_t int32_t uintptr_t intptr_t)
  check_c_source_compiles("
    #include <stdint.h>
    int main(void) { ${STDINT_TYPE} a = 123; (void)a; return 0; }
  " CC_TEST_${STDINT_TYPE})
  if(NOT CC_TEST_${STDINT_TYPE})
    message(FATAL_ERROR "cannot use type ${STDINT_TYPE}")
  endif()
endforeach()

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
  COMMAND ${Python3_EXECUTABLE} makealias.py . ${DOT_ALIAS_H} ${DOT_ALIAS_IN}
  WORKING_DIRECTORY ${DOT_SRC}
  DEPENDS Python3::Interpreter ${DOT_SRC}/makealias.py ${DOT_ALIAS_IN}
)
###
set(ORTH_NAMES
  aa ab af am ar as ast av ay az_az az_ir ba bm be bg bh bho bi bin bn bo br bs
  bua ca ce ch chm chr co cs cu cv cy da de dz el en eo es et eu fa fi fj fo fr
  ff fur fy ga gd gez gl gn gu gv ha haw he hi ho hr hu hy ia ig id ie ik io is
  it iu ja ka kaa ki kk kl km kn ko kok ks ku_am ku_ir kum kv kw ky la lb lez ln
  lo lt lv mg mh mi mk ml mn_cn mo mr mt my nb nds ne nl nn no nr nso ny oc om
  or os pa pl ps_af ps_pk pt rm ro ru sa sah sco se sel sh shs si sk sl sm sma
  smj smn sms so sq sr ss st sv sw syr ta te tg th ti_er ti_et tig tk tl tn to
  tr ts tt tw tyv ug uk ur uz ve vi vo vot wa wen wo xh yap yi yo zh_cn zh_hk
  zh_mo zh_sg zh_tw zu ak an ber_dz ber_ma byn crh csb dv ee fat fil hne hsb ht
  hz ii jv kab kj kr ku_iq ku_tr kwm lg li mai mn_mn ms na ng nv ota pa_pk pap_an
  pap_aw qu quz rn rw sc sd sg sid sn su ty wal za lah nqo brx sat doi mni und_zsye
  und_zmth anp bhb hif mag raj the agr ayc bem ckb cmn dsb hak lij lzh mfe mhr
  miq mjw mnw nan nhn niu rif sgs shn szl tcy tpi unm wae yue yuw got cop suz)
# sync the above list.

list(TRANSFORM ORTH_NAMES APPEND .orth)

set(DOT_FCLANG ${CMAKE_CURRENT_SOURCE_DIR}/fc-lang)
list(TRANSFORM ORTH_NAMES PREPEND ${DOT_FCLANG}/ OUTPUT_VARIABLE ORTH_FILES)

add_custom_command(
  OUTPUT ${DOT_GEN_H}/fclang.h
  COMMAND ${CMAKE_COMMAND} -E make_directory ${DOT_GEN_H}
  COMMAND ${Python3_EXECUTABLE} fc-lang.py ${ORTH_NAMES} --template fclang.tmpl.h --output ${DOT_GEN_H}/fclang.h
  WORKING_DIRECTORY ${DOT_FCLANG}
  DEPENDS Python3::Interpreter ${DOT_FCLANG}/fc-lang.py ${DOT_FCLANG}/fclang.tmpl.h ${ORTH_FILES}
)
###
set(DOT_FCCONST ${CMAKE_CURRENT_SOURCE_DIR}/fc-const)

add_custom_command(
  OUTPUT ${DOT_GEN_H}/fcconst.h
  COMMAND ${CMAKE_COMMAND} -E make_directory ${DOT_GEN_H}
  COMMAND ${Python3_EXECUTABLE} fc-const.py fcconst.list ${DOT_SRC}/fcobjs.h -o ${DOT_GEN_H}/fcconst.h
  WORKING_DIRECTORY ${DOT_FCCONST}
  DEPENDS Python3::Interpreter ${DOT_FCCONST}/fc-const.py ${DOT_FCCONST}/fcconst.list ${DOT_SRC}/fcobjs.h
)
###

add_custom_target(dropout_generated_headers DEPENDS
  ${DOT_GEN_H}/fcstdint.h
  ${DOT_FC_H}
  ${DOT_ALIAS_H}
  ${DOT_GEN_H}/config.h
  ${DOT_GEN_H}/fclang.h
  ${DOT_GEN_H}/fcconst.h)

add_library(fontconfig SHARED
  src/fcobjs.c
  src/fcname.c
  src/fcstat.c
  src/fccache.c
  src/fcinit.c
  src/fccfg.c
  src/fcdefault.c
  src/fcpat.c
  src/fcmatch.c
  src/fcdbg.c)
if(CC_TEST_FAM)
  target_compile_definitions(fontconfig PRIVATE -DFLEXIBLE_ARRAY_MEMBER)
else()
  target_compile_definitions(fontconfig PRIVATE FLEXIBLE_ARRAY_MEMBER=1)
endif()
target_compile_definitions(fontconfig PRIVATE -DHAVE_CONFIG_H)
add_dependencies(fontconfig
  dropout_generated_headers)
target_include_directories(fontconfig PRIVATE
  ${DOT_GEN_H})
target_link_libraries(fontconfig PRIVATE
  EXPAT::EXPAT
  Freetype::Freetype)
