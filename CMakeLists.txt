cmake_minimum_required(VERSION 3.16)
project(libcamera_cpp_app LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)

find_package(Iconv QUIET)
if(NOT TARGET Iconv::Iconv)
  add_library(Iconv::Iconv INTERFACE IMPORTED)
  if(Iconv_FOUND)
    target_include_directories(Iconv::Iconv INTERFACE ${Iconv_INCLUDE_DIRS})
    target_link_libraries(Iconv::Iconv INTERFACE ${Iconv_LIBRARIES})
  endif()
endif()

find_package(OpenCV REQUIRED COMPONENTS core imgproc imgcodecs)
pkg_check_modules(LIBCAMERA REQUIRED libcamera)

add_executable(libcamera_cpp_app main.cpp)

target_include_directories(libcamera_cpp_app PRIVATE
  ${LIBCAMERA_INCLUDE_DIRS}
  ${OpenCV_INCLUDE_DIRS}
)

target_link_directories(libcamera_cpp_app PRIVATE
  ${LIBCAMERA_LIBRARY_DIRS}
)

target_link_libraries(libcamera_cpp_app PRIVATE
  ${LIBCAMERA_LIBRARIES}
  ${OpenCV_LIBS}
)

target_compile_options(libcamera_cpp_app PRIVATE
  ${LIBCAMERA_CFLAGS_OTHER}
)