#pragma once
#define CIMGUI_DEFINE_ENUMS_AND_STRUCTS

#ifdef __cplusplus
extern "C" {
#endif

struct ImFontAtlas;
bool igFt_BuildFontAtlas(struct ImFontAtlas* font, unsigned int extra_flags);

#ifdef __cplusplus
}
#endif
