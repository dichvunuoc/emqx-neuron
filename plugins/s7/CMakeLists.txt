set(LIBRARY_OUTPUT_PATH "${CMAKE_BINARY_DIR}/plugins")
set(CMAKE_BUILD_RPATH ./)

set(S7_COMMON_SRC s7_plugin.c s7_addr.c)

file(COPY ${CMAKE_SOURCE_DIR}/plugins/s7/s7comm.json
     DESTINATION ${CMAKE_BINARY_DIR}/plugins/schema/)
file(COPY ${CMAKE_SOURCE_DIR}/plugins/s7/s7comm_for_300.json
     DESTINATION ${CMAKE_BINARY_DIR}/plugins/schema/)

list(APPEND CMAKE_FIND_ROOT_PATH "/usr/local" "/opt/homebrew")
if(DEFINED ENV{SNAP7_ROOT})
  list(APPEND CMAKE_FIND_ROOT_PATH "$ENV{SNAP7_ROOT}")
endif()

set(SNAP7_VENDOR_DIR ${CMAKE_CURRENT_SOURCE_DIR})
find_path(SNAP7_INCLUDE_DIR snap7.h
  HINTS "${CMAKE_PREFIX_PATH}" ENV CMAKE_PREFIX_PATH ENV SNAP7_ROOT
  PATHS ${SNAP7_VENDOR_DIR} /usr/local /opt/homebrew
  PATH_SUFFIXES include "")
find_library(SNAP7_LIBRARY NAMES snap7
  HINTS "${CMAKE_PREFIX_PATH}" ENV CMAKE_PREFIX_PATH ENV SNAP7_ROOT
  PATHS ${SNAP7_VENDOR_DIR}/lib /usr/local/lib /opt/homebrew/lib
        /tmp/snap7/build/bin/x86_64-osx /tmp/snap7/build/bin/x86_64-linux)

macro(neuron_s7_plugin TARGET ENTRY)
  add_library(${TARGET} SHARED)
  target_include_directories(${TARGET} PRIVATE ${CMAKE_SOURCE_DIR}/include/neuron)
  target_sources(${TARGET} PRIVATE ${S7_COMMON_SRC} ${ENTRY})
  target_link_libraries(${TARGET} neuron-base)
  if(SNAP7_INCLUDE_DIR AND SNAP7_LIBRARY)
    message(STATUS "snap7 found for ${TARGET}: ${SNAP7_LIBRARY}")
    target_compile_definitions(${TARGET} PRIVATE NEU_S7_HAS_SNAP7=1)
    target_include_directories(${TARGET} PRIVATE ${SNAP7_INCLUDE_DIR})
    target_link_libraries(${TARGET} ${SNAP7_LIBRARY})
    if(UNIX AND NOT APPLE)
      target_link_libraries(${TARGET} pthread)
    endif()
  else()
    message(WARNING "snap7 not found, ${TARGET} builds with runtime-disabled fallback")
    target_compile_definitions(${TARGET} PRIVATE NEU_S7_HAS_SNAP7=0)
  endif()
endmacro()

neuron_s7_plugin(plugin-s7comm s7comm.c)
neuron_s7_plugin(plugin-s7comm_for_300 s7comm_for_300.c)
