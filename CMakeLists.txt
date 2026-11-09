cmake_minimum_required(VERSION 3.21)
project(truedrive_cli LANGUAGES C)

option(TRUEDRIVE_SANITIZE "Check for memory errors at run time, at the cost of speed" OFF)
set(TRUEDRIVE_CORE_DIR "" CACHE PATH "Checkout of the core library, found automatically when empty")

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE RelWithDebInfo CACHE STRING "Build type" FORCE)
endif()

# The core library: the "modules/core" git submodule, or the parent folder while this
# project still sits inside the core repository.
if(TRUEDRIVE_CORE_DIR)
  cmake_path(ABSOLUTE_PATH TRUEDRIVE_CORE_DIR BASE_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR} NORMALIZE OUTPUT_VARIABLE CORE_DIR)
elseif(NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/modules/core/CMakeLists.txt AND EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/../include/truedrive.h)
  cmake_path(GET CMAKE_CURRENT_SOURCE_DIR PARENT_PATH CORE_DIR)
else()
  set(CORE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/modules/core)
endif()

if(NOT EXISTS ${CORE_DIR}/CMakeLists.txt)
  message(FATAL_ERROR "Core library not found in '${CORE_DIR}'. Run: git submodule update --init")
endif()

add_subdirectory(${CORE_DIR} ${CMAKE_CURRENT_BINARY_DIR}/core)

# Named apart from the library target, while the program itself is "truedrive".
add_executable(truedrive-cli src/main.c)
set_target_properties(truedrive-cli PROPERTIES OUTPUT_NAME truedrive)
target_compile_features(truedrive-cli PRIVATE c_std_11)
target_compile_options(truedrive-cli PRIVATE -Wall -Wextra)
target_link_libraries(truedrive-cli PRIVATE truedrive::truedrive)

enable_testing()
add_test(NAME cli COMMAND sh ${CMAKE_CURRENT_SOURCE_DIR}/tests/run.sh $<TARGET_FILE:truedrive-cli>)
