# Kivo's on-device language model runtime: a thin JNI layer over llama.cpp.
# Built by the Android Gradle Plugin for the phone and by plain CMake on a PC for the JVM tests.
cmake_minimum_required(VERSION 3.22)
project(kivo_llama C CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# llama.cpp, pinned. Pass -DLLAMA_DIR=/path/to/llama.cpp to use a local checkout instead of fetching.
set(LLAMA_TAG "b6500")
if(NOT LLAMA_DIR)
    include(FetchContent)
    FetchContent_Declare(llama_src GIT_REPOSITORY https://github.com/ggml-org/llama.cpp.git GIT_TAG ${LLAMA_TAG} GIT_SHALLOW TRUE)
    FetchContent_GetProperties(llama_src)
    if(NOT llama_src_POPULATED)
        FetchContent_Populate(llama_src)
    endif()
    set(LLAMA_DIR ${llama_src_SOURCE_DIR})
endif()

set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
if(ANDROID)
    # one binary for every phone of the ABI: no build-machine specific CPU flags
    set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
endif()
add_subdirectory(${LLAMA_DIR} llama-build EXCLUDE_FROM_ALL)

add_library(kivo_llama SHARED kivo_llama.cpp)
target_include_directories(kivo_llama PRIVATE ${LLAMA_DIR}/include ${LLAMA_DIR}/ggml/include)
target_link_libraries(kivo_llama PRIVATE llama)

if(ANDROID)
    target_link_libraries(kivo_llama PRIVATE log)
    # Android 15+ devices may use 16 KB memory pages
    target_link_options(kivo_llama PRIVATE "-Wl,-z,max-page-size=16384")
else()
    find_package(JNI REQUIRED)
    target_include_directories(kivo_llama PRIVATE ${JNI_INCLUDE_DIRS})
endif()
