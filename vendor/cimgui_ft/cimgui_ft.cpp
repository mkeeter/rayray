#include "cimgui_ft.h"
#include "misc/freetype/imgui_freetype.h"

bool igFt_BuildFontAtlas(struct ImFontAtlas* font, unsigned int extra_flags) {
    return ImGuiFreeType::BuildFontAtlas(font, extra_flags);
}
