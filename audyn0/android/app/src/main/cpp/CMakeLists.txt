cmake_minimum_required(VERSION 3.10)
project(libtorrentwrapper)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Include paths - adjust to your actual paths
include_directories(
        ${CMAKE_SOURCE_DIR}/include
        ${CMAKE_SOURCE_DIR}/boost/include
)

# Source file for the native wrapper
add_library(
        libtorrentwrapper
        SHARED
        LibtorrentWrapper.cpp
)

# Path to the prebuilt libtorrent native library for current Android ABI
set(LIBTORRENT_LIB_PATH ${CMAKE_SOURCE_DIR}/../jniLibs/${ANDROID_ABI}/libtorrent-rasterbar.so)

# Import the prebuilt libtorrent library
add_library(libtorrent SHARED IMPORTED)
set_target_properties(libtorrent PROPERTIES IMPORTED_LOCATION ${LIBTORRENT_LIB_PATH})

# Link libraries to your wrapper
target_link_libraries(
        libtorrentwrapper
        libtorrent         # Your imported libtorrent native library
        log                # Android logging
        android            # Android native library
        z                  # Compression library, needed by libtorrent
)
