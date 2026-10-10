#include "flutter_window.h"

#include <optional>

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "utaneko_activate.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::RegisterAspectChannel() {
  if (!flutter_controller_ || !flutter_controller_->engine()) {
    return;
  }
  aspect_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "utaneko/window_aspect",
          &flutter::StandardMethodCodec::GetInstance());
  aspect_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setAspectRatioLocked") {
          const auto* locked = std::get_if<bool>(call.arguments());
          if (locked == nullptr) {
            result->Error("bad_args", "Expected bool");
            return;
          }
          SetAspectRatioLocked(*locked);
          result->Success();
          return;
        }
        if (call.method_name() == "isAspectRatioLocked") {
          result->Success(flutter::EncodableValue(IsAspectRatioLocked()));
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::RegisterSecondInstanceChannel() {
  if (!flutter_controller_ || !flutter_controller_->engine()) {
    return;
  }
  // Host → Dart only (activate / clear boss-hide). No inbound handlers.
  second_instance_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "utaneko/second_instance",
          &flutter::StandardMethodCodec::GetInstance());
}

void FlutterWindow::NotifySecondInstanceActivate() {
  if (!second_instance_channel_) {
    return;
  }
  second_instance_channel_->InvokeMethod("activate", nullptr);
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
  RegisterAspectChannel();
  RegisterSecondInstanceChannel();
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

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
  aspect_channel_ = nullptr;
  second_instance_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Second exe asked us to foreground + clear boss-hide state in Dart.
  if (message == UtaNekoActivateMessage()) {
    NotifySecondInstanceActivate();
    return 0;
  }

  // 比例锁必须先于 Flutter，避免拖拽矩形被改回去。
  switch (message) {
    case WM_SIZING:
    case WM_WINDOWPOSCHANGING:
    case WM_GETMINMAXINFO:
      return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
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
