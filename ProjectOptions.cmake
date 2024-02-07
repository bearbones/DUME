include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(DUME_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(DUME_setup_options)
  option(DUME_ENABLE_HARDENING "Enable hardening" ON)
  option(DUME_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    DUME_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    DUME_ENABLE_HARDENING
    OFF)

  DUME_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR DUME_PACKAGING_MAINTAINER_MODE)
    option(DUME_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(DUME_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(DUME_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(DUME_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(DUME_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(DUME_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(DUME_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(DUME_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(DUME_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(DUME_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(DUME_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(DUME_ENABLE_PCH "Enable precompiled headers" OFF)
    option(DUME_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(DUME_ENABLE_IPO "Enable IPO/LTO" ON)
    option(DUME_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(DUME_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(DUME_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(DUME_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(DUME_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(DUME_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(DUME_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(DUME_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(DUME_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(DUME_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(DUME_ENABLE_PCH "Enable precompiled headers" OFF)
    option(DUME_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      DUME_ENABLE_IPO
      DUME_WARNINGS_AS_ERRORS
      DUME_ENABLE_USER_LINKER
      DUME_ENABLE_SANITIZER_ADDRESS
      DUME_ENABLE_SANITIZER_LEAK
      DUME_ENABLE_SANITIZER_UNDEFINED
      DUME_ENABLE_SANITIZER_THREAD
      DUME_ENABLE_SANITIZER_MEMORY
      DUME_ENABLE_UNITY_BUILD
      DUME_ENABLE_CLANG_TIDY
      DUME_ENABLE_CPPCHECK
      DUME_ENABLE_COVERAGE
      DUME_ENABLE_PCH
      DUME_ENABLE_CACHE)
  endif()

  DUME_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (DUME_ENABLE_SANITIZER_ADDRESS OR DUME_ENABLE_SANITIZER_THREAD OR DUME_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(DUME_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(DUME_global_options)
  if(DUME_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    DUME_enable_ipo()
  endif()

  DUME_supports_sanitizers()

  if(DUME_ENABLE_HARDENING AND DUME_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR DUME_ENABLE_SANITIZER_UNDEFINED
       OR DUME_ENABLE_SANITIZER_ADDRESS
       OR DUME_ENABLE_SANITIZER_THREAD
       OR DUME_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${DUME_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${DUME_ENABLE_SANITIZER_UNDEFINED}")
    DUME_enable_hardening(DUME_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(DUME_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(DUME_warnings INTERFACE)
  add_library(DUME_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  DUME_set_project_warnings(
    DUME_warnings
    ${DUME_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(DUME_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(DUME_options)
  endif()

  include(cmake/Sanitizers.cmake)
  DUME_enable_sanitizers(
    DUME_options
    ${DUME_ENABLE_SANITIZER_ADDRESS}
    ${DUME_ENABLE_SANITIZER_LEAK}
    ${DUME_ENABLE_SANITIZER_UNDEFINED}
    ${DUME_ENABLE_SANITIZER_THREAD}
    ${DUME_ENABLE_SANITIZER_MEMORY})

  set_target_properties(DUME_options PROPERTIES UNITY_BUILD ${DUME_ENABLE_UNITY_BUILD})

  if(DUME_ENABLE_PCH)
    target_precompile_headers(
      DUME_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(DUME_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    DUME_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(DUME_ENABLE_CLANG_TIDY)
    DUME_enable_clang_tidy(DUME_options ${DUME_WARNINGS_AS_ERRORS})
  endif()

  if(DUME_ENABLE_CPPCHECK)
    DUME_enable_cppcheck(${DUME_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(DUME_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    DUME_enable_coverage(DUME_options)
  endif()

  if(DUME_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(DUME_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(DUME_ENABLE_HARDENING AND NOT DUME_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR DUME_ENABLE_SANITIZER_UNDEFINED
       OR DUME_ENABLE_SANITIZER_ADDRESS
       OR DUME_ENABLE_SANITIZER_THREAD
       OR DUME_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    DUME_enable_hardening(DUME_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
