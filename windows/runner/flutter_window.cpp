#include "flutter_window.h"
#include <flutter/standard_method_codec.h>
#include <optional>
#include "flutter/generated_plugin_registrant.h"
#include "clipboard_image.h"
#include "resource.h"
#include "utils.h"
#include <shlobj.h>

namespace {
constexpr UINT kTrayMessage = WM_APP + 1;
constexpr UINT kOpen = 101;
constexpr UINT kQuit = 102;
const UINT kTaskbarCreated = RegisterWindowMessageW(L"TaskbarCreated");
}
FlutterWindow::FlutterWindow(const flutter::DartProject& project) : project_(project) {}
FlutterWindow::~FlutterWindow() {}

void FlutterWindow::Restore() {
  ShowWindow(GetHandle(), SW_RESTORE);
  SetForegroundWindow(GetHandle());
}
void FlutterWindow::AddTray() {
  tray_ = {};
  tray_.cbSize = sizeof(tray_);
  tray_.hWnd = GetHandle(); tray_.uID = 1;
  tray_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  tray_.uCallbackMessage = kTrayMessage;
  tray_.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(tray_.szTip, L"\u8f7b\u8d34");
  tray_available_ = Shell_NotifyIconW(NIM_ADD, &tray_) != FALSE;
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) return false;
  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
    frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) return false;
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
    flutter_controller_->engine()->messenger(), "lan_clip/native", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "supportDirectory") {
      PWSTR path = nullptr;
      if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &path))) {
        std::wstring folder(path); CoTaskMemFree(path);
        folder += L"\\LanClip";
        result->Success(flutter::EncodableValue(Utf8FromUtf16(folder.c_str())));
      } else { result->Error("directory", "Application data directory unavailable"); }
    } else if (call.method_name() == "writeImage") {
      const auto* bytes = call.arguments() ? std::get_if<std::vector<uint8_t>>(call.arguments()) : nullptr;
      if (bytes && WriteClipboardImage(GetHandle(), *bytes)) result->Success();
      else result->Error("clipboard", "Image could not be written to the clipboard");
    } else if (call.method_name() == "hide") {
      ShowWindow(GetHandle(), tray_available_ ? SW_HIDE : SW_MINIMIZE); result->Success();
    } else if (call.method_name() == "quit") {
      result->Success(); quitting_ = true; PostMessage(GetHandle(), WM_CLOSE, 0, 0);
    } else { result->NotImplemented(); }
  });
  AddTray();
  flutter_controller_->engine()->SetNextFrameCallback([&]() { Show(); });
  flutter_controller_->ForceRedraw();
  return true;
}
void FlutterWindow::OnDestroy() {
  Shell_NotifyIconW(NIM_DELETE, &tray_);
  channel_.reset(); flutter_controller_.reset();
  Win32Window::OnDestroy();
}
LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) noexcept {
  if (message == kTaskbarCreated) { AddTray(); return 0; }
  if (message == WM_CLOSE && !quitting_ && tray_available_) { ShowWindow(hwnd, SW_HIDE); return 0; }
  if (message == kTrayMessage) {
    if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) Restore();
    if (lparam == WM_RBUTTONUP) {
      POINT point; GetCursorPos(&point);
      HMENU menu = CreatePopupMenu();
      AppendMenuW(menu, MF_STRING, kOpen, L"\u6253\u5f00\u8f7b\u8d34");
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      AppendMenuW(menu, MF_STRING, kQuit, L"\u9000\u51fa\u8f7b\u8d34");
      SetForegroundWindow(hwnd);
      const UINT command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
        point.x, point.y, 0, hwnd, nullptr);
      DestroyMenu(menu);
      if (command == kOpen) Restore();
      else if (command == kQuit) { quitting_ = true; PostMessage(hwnd, WM_CLOSE, 0, 0); }
      PostMessage(hwnd, WM_NULL, 0, 0);
    }
    return 0;
  }
  if (message == WM_GETMINMAXINFO) {
    auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
    const UINT dpi = GetDpiForWindow(hwnd);
    info->ptMinTrackSize.x = MulDiv(500, static_cast<int>(dpi), 96);
    info->ptMinTrackSize.y = MulDiv(360, static_cast<int>(dpi), 96);
    return 0;
  }
  if (flutter_controller_) {
    const auto result = flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam, lparam);
    if (result) return *result;
  }
  if (message == WM_FONTCHANGE && flutter_controller_) flutter_controller_->engine()->ReloadSystemFonts();
  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
