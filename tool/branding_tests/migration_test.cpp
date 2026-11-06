#include "../../windows/runner/legacy_preferences.h"
#include <fstream>
#include <iostream>
#include <stdexcept>

void Check(bool value) {
  if (!value) throw std::runtime_error("Preference migration check failed");
}

int main() {
  namespace fs = std::filesystem;
  const auto root = fs::temp_directory_path() /
      (L"study-branding-test-" + std::to_wstring(
          std::chrono::steady_clock::now().time_since_epoch().count()));
  const auto old_file = root / L"com.example" / L"untitled" / L"shared_preferences.json";
  const auto new_file = root / L"Quản lý lịch học" / L"Quản lý lịch học" / L"shared_preferences.json";
  fs::create_directories(root);
  Check(MigrateLegacyPreferences(root));  // A fresh install needs no old file.
  fs::create_directories(old_file.parent_path());
  std::ofstream(old_file) << "synthetic-old-preferences";
  Check(MigrateLegacyPreferences(root));
  Check(fs::exists(old_file));
  std::string data;
  std::ifstream(new_file) >> data;
  Check(data == "synthetic-old-preferences");
  std::ofstream(new_file) << "synthetic-new-preferences";
  Check(MigrateLegacyPreferences(root));  // Existing current data wins.
  std::ifstream(new_file) >> data;
  Check(data == "synthetic-new-preferences");
  fs::remove(new_file); fs::remove(old_file);
  fs::remove(new_file.parent_path()); fs::remove(new_file.parent_path().parent_path());
  fs::remove(old_file.parent_path()); fs::remove(old_file.parent_path().parent_path());
  fs::remove(root);
  std::cout << "Fresh install, legacy copy and no-overwrite checks passed.\n";
}
