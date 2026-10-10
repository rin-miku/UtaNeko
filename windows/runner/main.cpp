#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utaneko_activate.h"
#include "utils.h"

namespace {

// Local\ = current user session only (portable / multi-user safe).
constexpr const wchar_t kSingleInstanceMutex[] =
    L"Local\\com.replastic.utaneko.single";
// Must match Win32Window class registration + Create title.
constexpr const wchar_t kWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr const wchar_t kWindowTitle[] = L"UtaNeko";

HWND FindExistingUtaNekoWindow() {
  HWND hwnd = ::FindWindowW(kWindowClass, kWindowTitle);
  if (hwnd != nullptr) {
    return hwnd;
  }
  return ::FindWindowW(nullptr, kWindowTitle);
}

void ActivateExistingWindow(HWND hwnd) {
  if (hwnd == nullptr) {
    return;
  }
  if (::IsIconic(hwnd)) {
    ::ShowWindow(hwnd, SW_RESTORE);
  } else {
    ::ShowWindow(hwnd, SW_SHOW);
  }

  HWND foreground = ::GetForegroundWindow();
  const DWORD foreground_tid =
      ::GetWindowThreadProcessId(foreground, nullptr);
  const DWORD this_tid = ::GetCurrentThreadId();
  if (foreground_tid != 0 && foreground_tid != this_tid) {
    ::AttachThreadInput(this_tid, foreground_tid, TRUE);
    ::BringWindowToTop(hwnd);
    ::SetForegroundWindow(hwnd);
    ::AttachThreadInput(this_tid, foreground_tid, FALSE);
  } else {
    ::BringWindowToTop(hwnd);
    ::SetForegroundWindow(hwnd);
  }
}

// true = this process is the sole instance and should continue.
// Keeps the mutex handle for the process lifetime.
bool TryBecomeSingleInstance() {
  HANDLE mutex =
      ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutex);
  if (mutex == nullptr) {
    return false;
  }
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    const HWND existing = FindExistingUtaNekoWindow();
    if (existing != nullptr) {
      // Ask first instance to reveal (clears boss-hide Dart state).
      ::PostMessageW(existing, UtaNekoActivateMessage(), 0, 0);
      // Also nudge the HWND up immediately for snappy feedback.
      ActivateExistingWindow(existing);
    } else {
      // Mutex held but window not found (still starting / tray edge case).
      ::MessageBoxW(nullptr, L"已有 UtaNeko 正在运行。", L"UtaNeko",
                    MB_OK | MB_ICONINFORMATION);
    }
    ::CloseHandle(mutex);
    return false;
  }

  // Intentionally not closed: released when the process exits.
  static HANDLE s_single_instance_mutex = mutex;
  (void)s_single_instance_mutex;
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  if (!TryBecomeSingleInstance()) {
    return EXIT_SUCCESS;
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  // 逻辑像素 540×960，即 9:16。Create 会按 DPI 换算成物理像素。
  Win32Window::Size size(540, 960);
  if (!window.Create(kWindowTitle, origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
