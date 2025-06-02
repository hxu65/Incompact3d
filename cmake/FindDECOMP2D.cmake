# Allow user to specify the I/O backend
option(IO_BACKEND "Set the I/O backend to use (e.g., adios2)" "")

# Add ADIOS2_USE_Derived_Variable definition if backend is adios2
if(IO_BACKEND STREQUAL "adios2")
  message(STATUS "I/O Backend set to ADIOS2")
  find_package(adios2 REQUIRED)
  add_definitions(-DADIOS2_USE_Derived_Variable=ON)
endif()

# Optionally allow user to provide a decomp2d install directory
set(decomp2d_DIR "" CACHE PATH "Path to 2decomp-fft install dir")
set(adios2_DIR "" CACHE PATH "Path to ADIOS2 CMake config")

# Attempt to find decomp2d
find_package(decomp2d PATHS ${decomp2d_DIR} NO_DEFAULT_PATH)

if (decomp2d_FOUND)
  message(STATUS "2decomp-fft FOUND at ${decomp2d_DIR}")
else()
  message(STATUS "2decomp-fft not found, attempting to build from source...")

  configure_file(${CMAKE_SOURCE_DIR}/cmake/decomp2d/downloadBuild2decomp.cmake.in
                 decomp2d-build/CMakeLists.txt)

  execute_process(COMMAND ${CMAKE_COMMAND} -G "${CMAKE_GENERATOR}" .
    RESULT_VARIABLE result
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/decomp2d-build)

  if(result)
    message(FATAL_ERROR "CMake step for 2decomp-fft failed: ${result}")
  else()
    message("CMake step for 2decomp-fft completed (${result}).")
  endif()

  execute_process(COMMAND ${CMAKE_COMMAND} --build .
    RESULT_VARIABLE result
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/decomp2d-build)

  if(result)
    message(FATAL_ERROR "Build step for 2decomp-fft failed: ${result}")
  endif()

  set(D2D_ROOT ${CMAKE_CURRENT_BINARY_DIR}/decomp2d-build/downloadBuild2decomp-prefix/src/downloadBuild2decomp-build)
  find_package(decomp2d REQUIRED PATHS ${D2D_ROOT})
endif()
