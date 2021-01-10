This is a minimal C API wrapper around `ImGuiFreeType.cpp`,
exposing the one function that we use (`ImGuiFreeType::BuildFontAtlas`).

It's possible to build this into `cimgui`, but that requires a rebuild,
so this avoids forking the `cimgui` submodule.
