#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shlobj.h>

#include "flutter_window.h"
#include "utils.h"
#include "legacy_preferences.h"

namespace {

constexpr wchar_t kOAuthRedirectScheme[] = L"com.example.untitled";

bool SetRegistryString(const wchar_t* key_path, const wchar_t* value_name,
                       const std::wstring& value) {
  HKEY key = nullptr;
  const LSTATUS open_status =
      RegCreateKeyExW(HKEY_CURRENT_USER, key_path, 0, nullptr, 0, KEY_SET_VALUE,
                      nullptr, &key, nullptr);
  if (open_status != ERROR_SUCCESS) {
    return false;
  }

  const DWORD value_size =
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
  const LSTATUS set_status = RegSetValueExW(
      key, value_name, 0, REG_SZ,
      reinterpret_cast<const BYTE*>(value.c_str()), value_size);
  RegCloseKey(key);
  return set_status == ERROR_SUCCESS;
}

bool RegisterOAuthRedirectScheme() {
  wchar_t executable_path[MAX_PATH] = {};
  const DWORD path_length =
      GetModuleFileNameW(nullptr, executable_path, MAX_PATH);
  if (path_length == 0 || path_length >= MAX_PATH) {
    return false;
  }

  const std::wstring scheme_key =
      L"Software\\Classes\\" + std::wstring(kOAuthRedirectScheme);
  const std::wstring command_key =
      scheme_key + L"\\shell\\open\\command";
  const std::wstring command =
      L"\"" + std::wstring(executable_path) + L"\" \"%1\"";
  return SetRegistryString(scheme_key.c_str(), nullptr,
                           L"URL:Quản lý lịch học OAuth Protocol") &&
         SetRegistryString(scheme_key.c_str(), L"URL Protocol", L"") &&
         SetRegistryString(command_key.c_str(), nullptr, command);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  if (!RegisterOAuthRedirectScheme()) {
    ::MessageBoxW(
        nullptr,
        L"Windows could not register the OAuth callback URL. "
        L"Google and Microsoft sign-in may not return to the application.",
        L"OAuth callback setup", MB_OK | MB_ICONWARNING);
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  PWSTR roaming = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_RoamingAppData, 0, nullptr,
                                   &roaming))) {
    return EXIT_FAILURE;
  }
  const bool preferences_ready = MigrateLegacyPreferences(roaming);
  ::CoTaskMemFree(roaming);
  if (!preferences_ready) {
    ::MessageBoxW(nullptr,
        L"Chưa chuyển được dữ liệu từ bản demo cũ. Dữ liệu gốc vẫn được giữ. "
        L"Vui lòng đóng ứng dụng và kiểm tra quyền ghi thư mục ứng dụng.",
        L"Quản lý lịch học", MB_OK | MB_ICONERROR);
    return EXIT_FAILURE;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  // The runner is compiled with /utf-8 to preserve Vietnamese characters.
  if (!window.Create(L"Quản lý lịch học", origin, size)) {
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
