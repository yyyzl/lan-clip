#ifndef RUNNER_CLIPBOARD_IMAGE_H_
#define RUNNER_CLIPBOARD_IMAGE_H_
#include <windows.h>
#include <cstdint>
#include <vector>
bool WriteClipboardImage(HWND window, const std::vector<uint8_t>& png);
#endif
