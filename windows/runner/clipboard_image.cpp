#include "clipboard_image.h"
#include <wincodec.h>
#include <wrl/client.h>
#include <cstring>
#include <limits>

using Microsoft::WRL::ComPtr;

bool WriteClipboardImage(HWND window, const std::vector<uint8_t>& png) {
  if (png.empty() || png.size() > 20 * 1024 * 1024) return false;
  ComPtr<IWICImagingFactory> factory;
  if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER,
      IID_PPV_ARGS(&factory)))) return false;
  ComPtr<IWICStream> stream;
  if (FAILED(factory->CreateStream(&stream)) || FAILED(stream->InitializeFromMemory(
      const_cast<BYTE*>(png.data()), static_cast<DWORD>(png.size())))) return false;
  ComPtr<IWICBitmapDecoder> decoder;
  if (FAILED(factory->CreateDecoderFromStream(stream.Get(), nullptr, WICDecodeMetadataCacheOnLoad, &decoder))) return false;
  ComPtr<IWICBitmapFrameDecode> frame;
  if (FAILED(decoder->GetFrame(0, &frame))) return false;
  UINT width = 0, height = 0;
  if (FAILED(frame->GetSize(&width, &height)) || !width || !height ||
      static_cast<uint64_t>(width) * height > 24000000) return false;
  ComPtr<IWICFormatConverter> converter;
  if (FAILED(factory->CreateFormatConverter(&converter)) || FAILED(converter->Initialize(
      frame.Get(), GUID_WICPixelFormat32bppBGRA, WICBitmapDitherTypeNone, nullptr,
      0.0, WICBitmapPaletteTypeCustom))) return false;
  const UINT stride = width * 4;
  const UINT pixels_size = stride * height;
  std::vector<BYTE> pixels(pixels_size);
  if (FAILED(converter->CopyPixels(nullptr, stride, pixels_size, pixels.data()))) return false;

  HGLOBAL dibv5 = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, sizeof(BITMAPV5HEADER) + pixels_size);
  HGLOBAL dib = GlobalAlloc(GMEM_MOVEABLE | GMEM_ZEROINIT, sizeof(BITMAPINFOHEADER) + pixels_size);
  HGLOBAL encoded = GlobalAlloc(GMEM_MOVEABLE, png.size());
  if (!dibv5 || !dib || !encoded) {
    if (dibv5) GlobalFree(dibv5);
    if (dib) GlobalFree(dib);
    if (encoded) GlobalFree(encoded);
    return false;
  }
  auto* v5 = static_cast<BITMAPV5HEADER*>(GlobalLock(dibv5));
  auto* info = static_cast<BITMAPINFOHEADER*>(GlobalLock(dib));
  void* png_memory = GlobalLock(encoded);
  if (!v5 || !info || !png_memory) {
    if (v5) GlobalUnlock(dibv5);
    if (info) GlobalUnlock(dib);
    if (png_memory) GlobalUnlock(encoded);
    GlobalFree(dibv5); GlobalFree(dib); GlobalFree(encoded);
    return false;
  }
  v5->bV5Size = sizeof(BITMAPV5HEADER);
  v5->bV5Width = static_cast<LONG>(width); v5->bV5Height = -static_cast<LONG>(height);
  v5->bV5Planes = 1; v5->bV5BitCount = 32; v5->bV5Compression = BI_BITFIELDS;
  v5->bV5SizeImage = pixels_size;
  v5->bV5RedMask = 0x00ff0000; v5->bV5GreenMask = 0x0000ff00;
  v5->bV5BlueMask = 0x000000ff; v5->bV5AlphaMask = 0xff000000;
  v5->bV5CSType = LCS_sRGB;
  std::memcpy(reinterpret_cast<BYTE*>(v5) + sizeof(BITMAPV5HEADER), pixels.data(), pixels_size);
  info->biSize = sizeof(BITMAPINFOHEADER); info->biWidth = static_cast<LONG>(width);
  info->biHeight = -static_cast<LONG>(height); info->biPlanes = 1;
  info->biBitCount = 32; info->biCompression = BI_RGB; info->biSizeImage = pixels_size;
  auto* flat = reinterpret_cast<BYTE*>(info) + sizeof(BITMAPINFOHEADER);
  // Legacy CF_DIB has no alpha: composite onto white for old applications.
  for (size_t i = 0; i < pixels.size(); i += 4) {
    const unsigned a = pixels[i + 3];
    for (size_t channel = 0; channel < 3; ++channel)
      flat[i + channel] = static_cast<BYTE>((pixels[i + channel] * a + 255 * (255 - a) + 127) / 255);
    flat[i + 3] = 0;
  }
  std::memcpy(png_memory, png.data(), png.size());
  GlobalUnlock(dibv5); GlobalUnlock(dib); GlobalUnlock(encoded);
  if (!OpenClipboard(window)) { GlobalFree(dibv5); GlobalFree(dib); GlobalFree(encoded); return false; }
  if (!EmptyClipboard()) { CloseClipboard(); GlobalFree(dibv5); GlobalFree(dib); GlobalFree(encoded); return false; }
  bool success = false;
  if (SetClipboardData(CF_DIBV5, dibv5)) success = true; else GlobalFree(dibv5);
  if (SetClipboardData(CF_DIB, dib)) success = true; else GlobalFree(dib);
  const UINT png_format = RegisterClipboardFormatW(L"PNG");
  if (png_format && SetClipboardData(png_format, encoded)) success = true; else GlobalFree(encoded);
  CloseClipboard();
  return success;
}
