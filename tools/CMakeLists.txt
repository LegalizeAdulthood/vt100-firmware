add_executable(write-checksum
    write-checksum.cpp
)
target_compile_features(write-checksum PRIVATE cxx_std_11)
target_folder(write-checksum "Tools")
