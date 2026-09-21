cmake_minimum_required(VERSION 3.16)
project(nostalgia_bridge LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# TDLib is built from source by scripts/build-tdlib.sh into third_party/td-install.
list(APPEND CMAKE_PREFIX_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/td-install")
find_package(Td REQUIRED)

add_library(td_session STATIC src/providers/telegram/td_session.cpp)
target_include_directories(td_session PUBLIC src)
target_link_libraries(td_session PUBLIC Td::TdStatic)
target_compile_options(td_session PRIVATE -Wall -Wextra)

# M2: standalone probe, independent of ICQ.
add_executable(tg-probe src/providers/telegram/tg_probe.cpp)
target_link_libraries(tg-probe PRIVATE td_session)
target_compile_options(tg-probe PRIVATE -Wall -Wextra)
