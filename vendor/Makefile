all:
	@echo "Usage: make [wgpu|shaderc|imgui]"

.PHONY: wgpu shaderc imgui

WGPU=wgpu-macos-64-release.zip
wgpu:
	@echo "Building wgpu-native (untested, good luck!)"
	git clone https://github.com/gfx-rs/wgpu-native/
	cd wgpu-native && git checkout 3317a65 && cargo build --release
	mkdir -p wgpu
	cp wgpu-native/target/release/libwgpu_native.dylib wgpu
	cp wgpu-native/ffi/wgpu.h wgpu
	cd wgpu && install_name_tool -id "@executable_path/../../vendor/wgpu/libwgpu_native.dylib" libwgpu_native.dylib

SHADERC=install.tgz
shaderc:
	wget https://storage.googleapis.com/shaderc/artifacts/prod/graphics_shader_compiler/shaderc/macos/continuous_clang_release/347/20200903-075048/${SHADERC}
	tar -xvzf ${SHADERC}
	rm ${SHADERC}
	mv install shaderc

imgui:
	git submodule update --init --recursive
