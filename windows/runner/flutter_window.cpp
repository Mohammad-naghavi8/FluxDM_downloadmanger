#include "flutter_window.h"

#include <cwchar>
#include <optional>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr UINT kTrayCallbackMessage = WM_APP + 1;
constexpr UINT kTrayIconId = 1001;
constexpr UINT_PTR kTrayMenuShow = 2001;
constexpr UINT_PTR kTrayMenuHide = 2002;
constexpr UINT_PTR kTrayMenuExit = 2003;
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {
  RemoveSystemTray();
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Register Windows System Tray icon immediately on launch.
  taskbar_created_msg_ = RegisterWindowMessageW(L"TaskbarCreated");
  InitSystemTray();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveSystemTray();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::InitSystemTray() {
  HWND hwnd = GetHandle();
  if (!hwnd || tray_added_) {
    return;
  }

  const int sm_cx = GetSystemMetrics(SM_CXSMICON);
  const int sm_cy = GetSystemMetrics(SM_CYSMICON);
  tray_hicon_ = static_cast<HICON>(LoadImageW(
      GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
      sm_cx, sm_cy, LR_DEFAULTCOLOR));
  if (!tray_hicon_) {
    tray_hicon_ = LoadIconW(GetModuleHandleW(nullptr),
                            MAKEINTRESOURCEW(IDI_APP_ICON));
  }

  ZeroMemory(&tray_icon_, sizeof(tray_icon_));
  tray_icon_.cbSize = sizeof(NOTIFYICONDATAW);
  tray_icon_.hWnd = hwnd;
  tray_icon_.uID = kTrayIconId;
  tray_icon_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  tray_icon_.uCallbackMessage = kTrayCallbackMessage;
  tray_icon_.hIcon = tray_hicon_;
  wcsncpy_s(tray_icon_.szTip, L"FluxDM — Download Manager", _TRUNCATE);

  tray_added_ = Shell_NotifyIconW(NIM_ADD, &tray_icon_) == TRUE;
}

void FlutterWindow::RemoveSystemTray() {
  if (tray_added_) {
    Shell_NotifyIconW(NIM_DELETE, &tray_icon_);
    tray_added_ = false;
  }
  if (tray_hicon_) {
    DestroyIcon(tray_hicon_);
    tray_hicon_ = nullptr;
  }
}

void FlutterWindow::RestoreFromTray(HWND hwnd) {
  if (!hwnd) return;
  if (!IsWindowVisible(hwnd)) {
    ShowWindow(hwnd, SW_SHOW);
  }
  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  }
  SetForegroundWindow(hwnd);
}

void FlutterWindow::ShowTrayContextMenu(HWND hwnd) {
  HMENU menu = CreatePopupMenu();
  if (!menu) return;

  const bool visible = IsWindowVisible(hwnd) != FALSE && !IsIconic(hwnd);
  AppendMenuW(menu, MF_STRING, kTrayMenuShow, L"Show FluxDM");
  SetMenuDefaultItem(menu, static_cast<UINT>(kTrayMenuShow), FALSE);
  AppendMenuW(menu, visible ? MF_STRING : MF_STRING | MF_GRAYED,
              kTrayMenuHide, L"Hide to Tray");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayMenuExit, L"Exit FluxDM");

  POINT pt{};
  GetCursorPos(&pt);

  // Required by Win32 so clicking outside dismisses the tray popup menu.
  SetForegroundWindow(hwnd);
  const UINT cmd = static_cast<UINT>(TrackPopupMenu(
      menu, TPM_RIGHTBUTTON | TPM_RETURNCMD | TPM_NONOTIFY, pt.x, pt.y, 0,
      hwnd, nullptr));
  DestroyMenu(menu);
  PostMessageW(hwnd, WM_NULL, 0, 0);

  if (cmd == kTrayMenuShow) {
    RestoreFromTray(hwnd);
  } else if (cmd == kTrayMenuHide) {
    ShowWindow(hwnd, SW_HIDE);
  } else if (cmd == kTrayMenuExit) {
    RemoveSystemTray();
    DestroyWindow(hwnd);
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Re-add the tray icon automatically if Windows Explorer restarts.
  if (taskbar_created_msg_ != 0 && message == taskbar_created_msg_) {
    tray_added_ = false;
    InitSystemTray();
    return 0;
  }

  // Handle System Tray clicks.
  if (message == kTrayCallbackMessage) {
    const UINT evt = LOWORD(static_cast<DWORD>(lparam));
    if (evt == WM_LBUTTONUP || evt == WM_LBUTTONDBLCLK) {
      RestoreFromTray(hwnd);
      return 0;
    }
    if (evt == WM_RBUTTONUP || evt == WM_CONTEXTMENU) {
      ShowTrayContextMenu(hwnd);
      return 0;
    }
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
