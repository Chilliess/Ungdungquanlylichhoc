#ifndef RUNNER_LEGACY_PREFERENCES_H_
#define RUNNER_LEGACY_PREFERENCES_H_

#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <chrono>
#include <filesystem>
#include <string>

// path_provider_windows derives its directory from CompanyName/ProductName.
// Copy only our legacy preference file, preserving both the original and any
// existing preferences for the newly branded app. Never merge auth sessions.
inline bool MigrateLegacyPreferences(const std::filesystem::path& roaming) {
  namespace fs = std::filesystem;
  const auto source = roaming / L"com.example" / L"untitled" /
                      L"shared_preferences.json";
  const auto target = roaming / L"Quản lý lịch học" / L"Quản lý lịch học" /
                      L"shared_preferences.json";
  std::error_code error;
  if (fs::exists(target, error)) return fs::is_regular_file(target, error);
  if (error) return false;
  if (!fs::exists(source, error)) return !error;
  if (!fs::is_regular_file(source, error) || error) return false;
  fs::create_directories(target.parent_path(), error);
  if (error) return false;
  auto staged = target;
  staged += L".migration-" + std::to_wstring(
      std::chrono::steady_clock::now().time_since_epoch().count());
  if (!fs::copy_file(source, staged, fs::copy_options::none, error)) return false;
  // Unlike a replacing rename, this fails if another instance created target.
  if (::MoveFileExW(staged.c_str(), target.c_str(), 0)) return true;
  // A second instance might have completed the migration first.
  std::error_code cleanup;
  fs::remove(staged, cleanup);
  return fs::is_regular_file(target, cleanup) && !cleanup;
}

#endif  // RUNNER_LEGACY_PREFERENCES_H_
