set(HEADER_FILE ${CMAKE_CURRENT_LIST_DIR}/../include/neuron/version.h)
set(HEADER_TMPL ${CMAKE_CURRENT_LIST_DIR}/../version.h.in)
set(VERSION_FILE ${CMAKE_CURRENT_LIST_DIR}/../version)

# versions
file(STRINGS ${VERSION_FILE} NEURON_VERSION)
string(REPLACE "." ";" VERSION_LIST ${NEURON_VERSION})
list(GET VERSION_LIST 0 NEURON_VERSION_MAJOR)
list(GET VERSION_LIST 1 NEURON_VERSION_MINOR)
list(GET VERSION_LIST 2 NEURON_VERSION_MICRO)

# git revisions
execute_process(COMMAND git log --pretty=format:'%h' -n 1
  OUTPUT_VARIABLE GIT_REV
  ERROR_QUIET)

if ("${GIT_REV}" STREQUAL "")
  set(GIT_REV "N/A")
  set(GIT_DIFF "")
  set(GIT_TAG "N/A")
  set(GIT_BRANCH "N/A")
else()
  execute_process(COMMAND bash -c "git diff --quiet --exit-code || echo +dirty"
    OUTPUT_VARIABLE GIT_DIFF)
  execute_process(COMMAND git describe --exact-match --tags
    OUTPUT_VARIABLE GIT_TAG
    ERROR_QUIET)
  execute_process(COMMAND git rev-parse --abbrev-ref HEAD
    OUTPUT_VARIABLE GIT_BRANCH)

  string(STRIP "${GIT_REV}" GIT_REV)
  string(SUBSTRING "${GIT_REV}" 1 7 GIT_REV)
  string(STRIP "${GIT_DIFF}" GIT_DIFF)
  string(STRIP "${GIT_TAG}" GIT_TAG)
  string(STRIP "${GIT_BRANCH}" GIT_BRANCH)
endif()

# Container/release builds exclude .git from the build context. Allow the
# release pipeline to inject the same revision that is written to OCI labels.
if (DEFINED NEURON_VCS_REF AND
    NOT "${NEURON_VCS_REF}" STREQUAL "" AND
    NOT "${NEURON_VCS_REF}" STREQUAL "unknown")
  set(GIT_REV "${NEURON_VCS_REF}")
  set(GIT_DIFF "")
endif()

# build date
if (DEFINED NEURON_BUILD_DATE_OVERRIDE AND
    NOT "${NEURON_BUILD_DATE_OVERRIDE}" STREQUAL "" AND
    NOT "${NEURON_BUILD_DATE_OVERRIDE}" STREQUAL "unknown")
  string(LENGTH "${NEURON_BUILD_DATE_OVERRIDE}" BUILD_DATE_LENGTH)
  if (BUILD_DATE_LENGTH GREATER_EQUAL 10)
    string(SUBSTRING "${NEURON_BUILD_DATE_OVERRIDE}" 0 10 NEURON_BUILD_DATE)
  else()
    set(NEURON_BUILD_DATE "${NEURON_BUILD_DATE_OVERRIDE}")
  endif()
else()
  string(TIMESTAMP NEURON_BUILD_DATE "%Y-%m-%d")
endif()

# generate the header file
configure_file(${HEADER_TMPL} ${HEADER_FILE} @ONLY)
