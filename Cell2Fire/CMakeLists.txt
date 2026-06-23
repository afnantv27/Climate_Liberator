cmake_minimum_required(VERSION 3.16)
project(Cell2Fire
    VERSION   0.1.0
    LANGUAGES CXX
)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# ── Options ──────────────────────────────────────────────────────────
option(C2F_BUILD_CLI     "Build the Cell2Fire command-line executable"  ON)
option(C2F_BUILD_SHARED  "Build shared library (libcell2fire.dylib/.so)" OFF)
option(C2F_BUILD_TESTS   "Build unit tests"                            OFF)

# ── Dependencies ─────────────────────────────────────────────────────
find_package(OpenMP REQUIRED)
find_package(TIFF   REQUIRED)

# Boost — only need the random header-only component, but find the root
find_package(Boost REQUIRED)

# ── Engine source files (everything except main and the API wrapper) ─
set(ENGINE_SOURCES
    Cells.cpp
    DataGenerator.cpp
    FuelModelFBP.cpp
    FuelModelKitral.cpp
    FuelModelPortugal.cpp
    FuelModelRegistry.cpp
    FuelModelSpain.cpp
    FuelModelUtils.cpp
    Lightning.cpp
    ReadArgs.cpp
    ReadCSV.cpp
    Spotting.cpp
    WriteCSV.cpp
)

# Cell2Fire.cpp contains the Cell2Fire class AND main().
# We need the class for the library but NOT main() when building the lib.
# Strategy: compile Cell2Fire.cpp into the engine objects (main is excluded
# at link time for the library because the API wrapper provides the entry).
#
# NOTE: Cell2Fire.cpp defines main() at the bottom. When building the
# static library, the linker only pulls main() if something references it.
# For the CLI we add Cell2Fire.cpp directly. For the lib we still need
# the Cell2Fire class, so we include it and rely on the linker discarding
# the unreferenced main() symbol from the .a archive.
list(APPEND ENGINE_SOURCES Cell2Fire.cpp)

# ── Static library: libcell2fire.a ───────────────────────────────────
add_library(cell2fire_static STATIC
    ${ENGINE_SOURCES}
    cell2fire_api.cpp
)
target_include_directories(cell2fire_static
    PUBLIC  ${CMAKE_CURRENT_SOURCE_DIR}
    PRIVATE ${Boost_INCLUDE_DIRS}
)
target_link_libraries(cell2fire_static
    PUBLIC  OpenMP::OpenMP_CXX
    PUBLIC  TIFF::TIFF
    PRIVATE ${CMAKE_DL_LIBS}
    PRIVATE Threads::Threads
)
target_compile_options(cell2fire_static PRIVATE
    -O3 -fno-strict-aliasing -fexceptions -DNDEBUG -DIL_STD
)
set_target_properties(cell2fire_static PROPERTIES
    OUTPUT_NAME cell2fire
    ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
)

find_package(Threads REQUIRED)

# ── Optional shared library ──────────────────────────────────────────
if(C2F_BUILD_SHARED)
    add_library(cell2fire_shared SHARED
        ${ENGINE_SOURCES}
        cell2fire_api.cpp
    )
    target_include_directories(cell2fire_shared
        PUBLIC  ${CMAKE_CURRENT_SOURCE_DIR}
        PRIVATE ${Boost_INCLUDE_DIRS}
    )
    target_link_libraries(cell2fire_shared
        PUBLIC  OpenMP::OpenMP_CXX
        PUBLIC  TIFF::TIFF
        PRIVATE ${CMAKE_DL_LIBS}
        PRIVATE Threads::Threads
    )
    target_compile_options(cell2fire_shared PRIVATE
        -O3 -fno-strict-aliasing -fexceptions -DNDEBUG -DIL_STD
    )
    set_target_properties(cell2fire_shared PROPERTIES
        OUTPUT_NAME cell2fire
        LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib"
    )
endif()

# ── CLI executable (same as the original makefile target) ────────────
if(C2F_BUILD_CLI)
    add_executable(Cell2Fire_cli Cell2Fire.cpp)
    # Link against the static lib so the CLI gets everything
    target_link_libraries(Cell2Fire_cli PRIVATE cell2fire_static)
    set_target_properties(Cell2Fire_cli PROPERTIES
        OUTPUT_NAME Cell2Fire
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    )
endif()

# ── Unit tests ───────────────────────────────────────────────────────
if(C2F_BUILD_TESTS)
    find_package(Catch2 3 QUIET)
    if(NOT Catch2_FOUND)
        find_package(Catch2 2 QUIET)
    endif()
    if(Catch2_FOUND)
        add_executable(test_cell2fire
            ../test/unit_tests/test_kitral.cpp
            FuelModelKitral.cpp
            FuelModelUtils.cpp
        )
        target_include_directories(test_cell2fire PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
        target_link_libraries(test_cell2fire PRIVATE cell2fire_static)
        if(TARGET Catch2::Catch2WithMain)
            target_link_libraries(test_cell2fire PRIVATE Catch2::Catch2WithMain)
        elseif(TARGET Catch2::Catch2)
            target_link_libraries(test_cell2fire PRIVATE Catch2::Catch2)
        endif()
        set_target_properties(test_cell2fire PROPERTIES
            RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
        )
    else()
        message(WARNING "Catch2 not found — skipping tests")
    endif()
endif()

# ── Install rules ────────────────────────────────────────────────────
include(GNUInstallDirs)

install(TARGETS cell2fire_static
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
)
install(FILES cell2fire_api.h
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/cell2fire
)
if(C2F_BUILD_CLI)
    install(TARGETS Cell2Fire_cli
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
    )
endif()
if(C2F_BUILD_SHARED)
    install(TARGETS cell2fire_shared
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    )
endif()

# ── Info target (similar to makefile info) ───────────────────────────
add_custom_target(info
    COMMAND ${CMAKE_COMMAND} -E echo "C++ Compiler: ${CMAKE_CXX_COMPILER}"
    COMMAND ${CMAKE_COMMAND} -E echo "C++ Standard: ${CMAKE_CXX_STANDARD}"
    COMMAND ${CMAKE_COMMAND} -E echo "Build Type:   ${CMAKE_BUILD_TYPE}"
    COMMAND ${CMAKE_COMMAND} -E echo "OpenMP:       ${OpenMP_CXX_FLAGS}"
    COMMAND ${CMAKE_COMMAND} -E echo "TIFF:         ${TIFF_LIBRARIES}"
    COMMAND ${CMAKE_COMMAND} -E echo "Boost:        ${Boost_INCLUDE_DIRS}"
    VERBATIM
)
