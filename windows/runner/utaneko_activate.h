#ifndef RUNNER_UTANEKO_ACTIVATE_H_
#define RUNNER_UTANEKO_ACTIVATE_H_

#include <windows.h>

// Shared by first/second process: ask running instance to fully activate
// (including clearing boss-hide Dart state via MethodChannel).
inline UINT UtaNekoActivateMessage() {
  static const UINT msg =
      ::RegisterWindowMessageW(L"com.replastic.utaneko.activate");
  return msg;
}

#endif  // RUNNER_UTANEKO_ACTIVATE_H_
