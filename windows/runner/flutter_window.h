#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shellapi.h>

#include <memory>

#include "win32_window.h"

// A window that hosts the FluxDM Flutter view and manages the Windows system
// tray icon.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void InitSystemTray();
  void RemoveSystemTray();
  void ShowTrayContextMenu(HWND hwnd);
  void RestoreFromTray(HWND hwnd);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Native Windows System Tray icon state.
  NOTIFYICONDATAW tray_icon_{};
  HICON tray_hicon_ = nullptr;
  bool tray_added_ = false;
  UINT taskbar_created_msg_ = 0;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
