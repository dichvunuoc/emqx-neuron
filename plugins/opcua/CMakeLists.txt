set(LIBRARY_OUTPUT_PATH "${CMAKE_BINARY_DIR}/plugins")

set(CMAKE_BUILD_RPATH ./)
file(COPY ${CMAKE_SOURCE_DIR}/plugins/opcua/opcua.json
     DESTINATION ${CMAKE_BINARY_DIR}/plugins/schema/)

set(OPCUA_PLUGIN plugin-opcua)
add_library(${OPCUA_PLUGIN} SHARED)
target_include_directories(${OPCUA_PLUGIN} PRIVATE ${CMAKE_SOURCE_DIR}/include/neuron)
target_sources(${OPCUA_PLUGIN} PRIVATE opcua.c)
target_link_libraries(${OPCUA_PLUGIN} neuron-base)

# Cross-toolchain sets CMAKE_FIND_ROOT_PATH to the staging sysroot only; allow host /usr/local for open62541.
list(APPEND CMAKE_FIND_ROOT_PATH "/usr/local")

find_path(OPEN62541_INCLUDE_DIR open62541/client.h
  HINTS "${CMAKE_PREFIX_PATH}" ENV CMAKE_PREFIX_PATH
  PATHS /usr/local /opt/homebrew
  PATH_SUFFIXES include)
find_library(OPEN62541_LIBRARY NAMES open62541
  HINTS "${CMAKE_PREFIX_PATH}" ENV CMAKE_PREFIX_PATH
  PATHS /usr/local/lib /opt/homebrew/lib)
if(OPEN62541_INCLUDE_DIR AND OPEN62541_LIBRARY)
  message(STATUS "open62541 found, enabling OPC UA runtime")
  target_compile_definitions(${OPCUA_PLUGIN} PRIVATE NEU_OPCUA_HAS_OPEN62541=1)
  target_include_directories(${OPCUA_PLUGIN} PRIVATE ${OPEN62541_INCLUDE_DIR})
  target_link_libraries(${OPCUA_PLUGIN} ${OPEN62541_LIBRARY})
else()
  message(WARNING "open62541 not found, plugin-opcua builds with runtime-disabled fallback")
  target_compile_definitions(${OPCUA_PLUGIN} PRIVATE NEU_OPCUA_HAS_OPEN62541=0)
endif()
