#include "win32_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include <algorithm>
#include <cmath>

#include "resource.h"

namespace {

/// Window attribute that enables dark mode window decorations.
///
/// Redefined in case the developer's machine has a Windows SDK older than
/// version 10.0.22000.0.
/// See: https://docs.microsoft.com/windows/win32/api/dwmapi/ne-dwmapi-dwmwindowattribute
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

/// Registry key for app theme preference.
///
/// A value of 0 indicates apps should use dark mode. A non-zero or missing
/// value indicates apps should use light mode.
constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";

// 窗口外框宽高比 9:16。拖拽、最大化、贴靠都按这个比例修正。
constexpr double kAspectWidthOverHeight = 9.0 / 16.0;

LONG AspectHeightForWidth(LONG width) {
  return std::max<LONG>(1, static_cast<LONG>(std::llround(
                               static_cast<double>(width) / kAspectWidthOverHeight)));
}

LONG AspectWidthForHeight(LONG height) {
  return std::max<LONG>(1, static_cast<LONG>(std::llround(
                               static_cast<double>(height) * kAspectWidthOverHeight)));
}

bool AspectMatches(LONG width, LONG height) {
  if (width <= 0 || height <= 0) {
    return true;
  }
  const double current =
      static_cast<double>(width) / static_cast<double>(height);
  return std::abs(current - kAspectWidthOverHeight) < 0.004;
}

void ApplyAspectToSizingRect(RECT* rect, WPARAM edge) {
  const LONG width = rect->right - rect->left;
  const LONG height = rect->bottom - rect->top;
  if (width <= 0 || height <= 0) {
    return;
  }

  LONG new_width = width;
  LONG new_height = height;
  switch (edge) {
    case WMSZ_TOP:
    case WMSZ_BOTTOM:
      new_width = AspectWidthForHeight(height);
      new_height = height;
      break;
    default:
      new_height = AspectHeightForWidth(width);
      new_width = width;
      break;
  }

  switch (edge) {
    case WMSZ_LEFT:
    case WMSZ_TOPLEFT:
    case WMSZ_BOTTOMLEFT:
      rect->left = rect->right - new_width;
      break;
    default:
      rect->right = rect->left + new_width;
      break;
  }

  switch (edge) {
    case WMSZ_TOP:
    case WMSZ_TOPLEFT:
    case WMSZ_TOPRIGHT:
      rect->top = rect->bottom - new_height;
      break;
    default:
      rect->bottom = rect->top + new_height;
      break;
  }
}

void LargestAspectSize(LONG box_w, LONG box_h, LONG* width, LONG* height) {
  LONG w = std::max<LONG>(1, box_w);
  LONG h = AspectHeightForWidth(w);
  if (h > box_h) {
    h = std::max<LONG>(1, box_h);
    w = AspectWidthForHeight(h);
  }
  if (w > box_w) {
    w = std::max<LONG>(1, box_w);
    h = AspectHeightForWidth(w);
  }
  *width = w;
  *height = h;
}

void FitSizeToWorkArea(LONG* width, LONG* height, LONG work_w, LONG work_h) {
  if (*width <= 0 || *height <= 0 || work_w <= 0 || work_h <= 0) {
    return;
  }
  if (*height > work_h) {
    *height = work_h;
    *width = AspectWidthForHeight(*height);
  }
  if (*width > work_w) {
    *width = work_w;
    *height = AspectHeightForWidth(*width);
  }
  if (*height > work_h) {
    *height = work_h;
    *width = AspectWidthForHeight(*height);
  }
}

// The number of Win32Window objects that currently exist.
static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);

// Scale helper to convert logical scaler values to physical using passed in
// scale factor
int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}

// Dynamically loads the |EnableNonClientDpiScaling| from the User32 module.
// This API is only needed for PerMonitor V1 awareness mode.
void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  // namespace

// Manages the Win32Window's window class registration.
class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  // Returns the singleton registrar instance.
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  // Returns the name of the window class, registering the class if it hasn't
  // previously been registered.
  const wchar_t* GetWindowClass();

  // Unregisters the window class. Should only be called if there are no
  // instances of the window.
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    window_class.style = CS_HREDRAW | CS_VREDRAW;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

void Win32Window::SetAspectRatioLocked(bool locked) {
  aspect_ratio_locked_ = locked;
}

bool Win32Window::IsAspectRatioLocked() const {
  return aspect_ratio_locked_;
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  LONG width = Scale(size.width, scale_factor);
  LONG height = Scale(size.height, scale_factor);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (GetMonitorInfo(monitor, &monitor_info)) {
    const LONG work_w = monitor_info.rcWork.right - monitor_info.rcWork.left;
    const LONG work_h = monitor_info.rcWork.bottom - monitor_info.rcWork.top;
    FitSizeToWorkArea(&width, &height, work_w, work_h);
  }

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      width, height,
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}

// static
LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;
      if (aspect_ratio_locked_ && !AspectMatches(newWidth, newHeight)) {
        newHeight = AspectHeightForWidth(newWidth);
      }

      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);

      return 0;
    }
    case WM_SIZING: {
      if (!aspect_ratio_locked_) {
        break;
      }
      auto* rect = reinterpret_cast<RECT*>(lparam);
      ApplyAspectToSizingRect(rect, wparam);
      return TRUE;
    }
    case WM_WINDOWPOSCHANGING: {
      if (!aspect_ratio_locked_) {
        break;
      }
      auto* pos = reinterpret_cast<WINDOWPOS*>(lparam);
      if ((pos->flags & SWP_NOSIZE) != 0 || IsIconic(hwnd)) {
        break;
      }
      if (pos->cx < 100 || pos->cy < 100 || AspectMatches(pos->cx, pos->cy)) {
        break;
      }

      RECT current{};
      GetWindowRect(hwnd, &current);
      const LONG cur_w = current.right - current.left;
      const LONG cur_h = current.bottom - current.top;
      const bool width_changed = pos->cx != cur_w;
      const bool height_changed = pos->cy != cur_h;
      if (width_changed && !height_changed) {
        pos->cy = AspectHeightForWidth(pos->cx);
      } else if (height_changed && !width_changed) {
        pos->cx = AspectWidthForHeight(pos->cy);
      } else {
        const LONG fitted_h = AspectHeightForWidth(pos->cx);
        if (fitted_h <= pos->cy) {
          pos->cy = fitted_h;
        } else {
          pos->cx = AspectWidthForHeight(pos->cy);
        }
      }

      HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      MONITORINFO info{};
      info.cbSize = sizeof(info);
      if (GetMonitorInfo(monitor, &info)) {
        const LONG work_w = info.rcWork.right - info.rcWork.left;
        const LONG work_h = info.rcWork.bottom - info.rcWork.top;
        LONG w = pos->cx;
        LONG h = pos->cy;
        FitSizeToWorkArea(&w, &h, work_w, work_h);
        pos->cx = w;
        pos->cy = h;
      }
      break;
    }
    case WM_GETMINMAXINFO: {
      auto result = DefWindowProc(hwnd, message, wparam, lparam);
      auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
      const UINT dpi = GetDpiForWindow(hwnd);
      const double scale = dpi > 0 ? dpi / 96.0 : 1.0;
      if (!aspect_ratio_locked_) {
        // Mini：允许扁长条，最小约 200×56 逻辑像素。
        info->ptMinTrackSize.x = static_cast<LONG>(200 * scale);
        info->ptMinTrackSize.y = static_cast<LONG>(56 * scale);
        return result;
      }
      info->ptMinTrackSize.x = static_cast<LONG>(360 * scale);
      info->ptMinTrackSize.y = static_cast<LONG>(640 * scale);

      HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
      MONITORINFO monitor_info{};
      monitor_info.cbSize = sizeof(monitor_info);
      if (GetMonitorInfo(monitor, &monitor_info)) {
        LONG max_w = 0;
        LONG max_h = 0;
        LargestAspectSize(
            monitor_info.rcWork.right - monitor_info.rcWork.left,
            monitor_info.rcWork.bottom - monitor_info.rcWork.top, &max_w,
            &max_h);
        info->ptMaxTrackSize.x = max_w;
        info->ptMaxTrackSize.y = max_h;
        info->ptMaxSize.x = max_w;
        info->ptMaxSize.y = max_h;
        if (info->ptMinTrackSize.x > max_w || info->ptMinTrackSize.y > max_h) {
          info->ptMinTrackSize.x = max_w;
          info->ptMinTrackSize.y = max_h;
        }
      }
      return result;
    }
    case WM_SIZE: {
      RECT rect = GetClientArea();
      if (child_content_ != nullptr) {
        // Size and position the child window.
        MoveWindow(child_content_, rect.left, rect.top, rect.right - rect.left,
                   rect.bottom - rect.top, TRUE);
      }
      return 0;
    }

    case WM_ACTIVATE:
      if (child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  // No-op; provided for subclasses.
  return true;
}

void Win32Window::OnDestroy() {
  // No-op; provided for subclasses.
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}
