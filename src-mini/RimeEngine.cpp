#include "RimeEngine.h"
#include "rime_api.h"
#include <shlobj.h>
#include <string>

static std::wstring Utf8ToW(const char* s) {
  if (!s || !*s) return L"";
  int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, nullptr, 0);
  std::wstring w(n ? n - 1 : 0, L'\0');
  if (n) MultiByteToWideChar(CP_UTF8, 0, s, -1, &w[0], n);
  return w;
}

static std::string WToUtf8(const std::wstring& w) {
  int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, nullptr, 0, nullptr, nullptr);
  std::string s(n ? n - 1 : 0, '\0');
  if (n) WideCharToMultiByte(CP_UTF8, 0, w.c_str(), -1, &s[0], n, nullptr, nullptr);
  return s;
}

RimeEngine& RimeEngine::Instance() {
  static RimeEngine inst;
  return inst;
}

typedef RimeApi* (*get_api_fn)();

static bool GetFileStamp(const std::wstring& path, FILETIME* ft) {
  WIN32_FILE_ATTRIBUTE_DATA fad;
  if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &fad))
    return false;
  *ft = fad.ftLastWriteTime;
  return true;
}

bool RimeEngine::EnsureInit(HINSTANCE dllModule) {
  if (initialized_) return true;
  if (initFailed_) return false;
  dllModule_ = dllModule;

  // rime.dll 与本 DLL 同目录
  wchar_t path[MAX_PATH];
  GetModuleFileNameW(dllModule, path, MAX_PATH);
  std::wstring dir(path);
  dir = dir.substr(0, dir.find_last_of(L'\\'));
  std::wstring rimePath = dir + L"\\rime.dll";
  rimeDll_ = LoadLibraryExW(rimePath.c_str(), nullptr,
                            LOAD_WITH_ALTERED_SEARCH_PATH);
  if (!rimeDll_) { initFailed_ = true; return false; }
  auto get_api = (get_api_fn)GetProcAddress(rimeDll_, "rime_get_api");
  if (!get_api) { initFailed_ = true; return false; }
  RimeApi* api = get_api();
  if (!api) { initFailed_ = true; return false; }
  api_ = api;

  // 用户目录 %APPDATA%\DashuaiMini（由 setup-mini.ps1 预先布好词库与 build）
  wchar_t appdata[MAX_PATH];
  SHGetFolderPathW(nullptr, CSIDL_APPDATA, nullptr, 0, appdata);
  std::wstring userDir = std::wstring(appdata) + L"\\DashuaiMini";
  std::wstring logDir = userDir + L"\\log";
  CreateDirectoryW(userDir.c_str(), nullptr);
  CreateDirectoryW(logDir.c_str(), nullptr);

  std::string userDirU8 = WToUtf8(userDir);
  std::string sharedU8 = WToUtf8(dir + L"\\data");
  std::string logU8 = WToUtf8(logDir);

  RIME_STRUCT(RimeTraits, traits);
  traits.shared_data_dir = sharedU8.c_str();
  traits.user_data_dir = userDirU8.c_str();
  traits.distribution_name = "大帅拼音·极简";
  traits.distribution_code_name = "dashuai-mini";
  traits.distribution_version = "0.1.0";
  traits.app_name = "rime.dashuai-mini";
  traits.min_log_level = 1;
  traits.log_dir = logU8.c_str();

  api->setup(&traits);
  api->initialize(&traits);
  // 词库已由安装脚本预编译复制，正常无需维护；若配置有变仅做快检
  if (api->start_maintenance(False)) api->join_maintenance_thread();
  session_ = api->create_session();
  if (!session_) { initFailed_ = true; return false; }
  initialized_ = true;
  // 记录 build 产物时间戳，用于配置热重载检测
  buildMarker_ = userDir + L"\\build\\wanxiang.schema.yaml";
  GetFileStamp(buildMarker_, &buildStamp_);
  return true;
}

void RimeEngine::MaybeReload() {
  if (!initialized_) return;
  unsigned long long now = GetTickCount64();
  if (now - lastReloadCheck_ < 3000) return;  // 3 秒节流
  lastReloadCheck_ = now;
  FILETIME ft;
  if (!GetFileStamp(buildMarker_, &ft)) return;
  if (CompareFileTime(&ft, &buildStamp_) == 0) return;
  // 词库/配置已重新部署 → 热重载引擎（一次性开销约 1-2 秒）
  RimeApi* api = (RimeApi*)api_;
  if (session_) api->destroy_session(session_);
  api->finalize();
  session_ = 0;
  initialized_ = false;
  initFailed_ = false;
  EnsureInit(dllModule_);
}

void RimeEngine::Finalize() {
  if (!initialized_) return;
  RimeApi* api = (RimeApi*)api_;
  if (session_) api->destroy_session(session_);
  api->finalize();
  session_ = 0;
  initialized_ = false;
}

void RimeEngine::RefreshState(MiniState& state) {
  RimeApi* api = (RimeApi*)api_;
  state.commit.clear();
  state.candidates.clear();
  state.preedit.clear();
  state.composing = false;

  RIME_STRUCT(RimeCommit, commit);
  if (api->get_commit(session_, &commit)) {
    state.commit = Utf8ToW(commit.text);
    api->free_commit(&commit);
  }

  RIME_STRUCT(RimeContext, ctx);
  if (api->get_context(session_, &ctx)) {
    if (ctx.composition.length > 0) {
      state.composing = true;
      state.preedit = Utf8ToW(ctx.composition.preedit);
      state.highlighted = ctx.menu.highlighted_candidate_index;
      state.page_no = ctx.menu.page_no;
      state.is_last_page = !!ctx.menu.is_last_page;
      for (int i = 0; i < ctx.menu.num_candidates; ++i) {
        MiniCandidate c;
        c.text = Utf8ToW(ctx.menu.candidates[i].text);
        c.comment = Utf8ToW(ctx.menu.candidates[i].comment);
        state.candidates.push_back(std::move(c));
      }
    }
    api->free_context(&ctx);
  }
}

bool RimeEngine::ProcessKey(int keysym, int mask, MiniState& state) {
  RimeApi* api = (RimeApi*)api_;
  if (!initialized_ || !keysym) return false;
  Bool handled = api->process_key(session_, keysym, mask);
  RefreshState(state);
  return !!handled;
}

void RimeEngine::ClearComposition(MiniState& state) {
  if (!initialized_) return;
  RimeApi* api = (RimeApi*)api_;
  api->clear_composition(session_);
  RefreshState(state);
}

bool RimeEngine::IsComposing() {
  if (!initialized_) return false;
  RimeApi* api = (RimeApi*)api_;
  RIME_STRUCT(RimeStatus, status);
  bool composing = false;
  if (api->get_status(session_, &status)) {
    composing = !!status.is_composing;
    api->free_status(&status);
  }
  return composing;
}

bool RimeEngine::GetAsciiMode() {
  if (!initialized_) return false;
  RimeApi* api = (RimeApi*)api_;
  return !!api->get_option(session_, "ascii_mode");
}

void RimeEngine::SetAsciiMode(bool ascii) {
  if (!initialized_) return;
  RimeApi* api = (RimeApi*)api_;
  api->set_option(session_, "ascii_mode", ascii ? True : False);
}

void RimeEngine::ToggleAsciiMode() {
  if (!initialized_) return;
  RimeApi* api = (RimeApi*)api_;
  Bool cur = api->get_option(session_, "ascii_mode");
  api->set_option(session_, "ascii_mode", !cur);
}

std::wstring RimeEngine::GetRawInput() {
  if (!initialized_) return L"";
  RimeApi* api = (RimeApi*)api_;
  const char* input = api->get_input(session_);
  return Utf8ToW(input);
}

// ---- VK -> X11 keysym ----
#define XK_BackSpace 0xFF08
#define XK_Return 0xFF0D
#define XK_Escape 0xFF1B
#define XK_Prior 0xFF55
#define XK_Next 0xFF56
#define XK_Left 0xFF51
#define XK_Up 0xFF52
#define XK_Right 0xFF53
#define XK_Down 0xFF54
#define XK_Home 0xFF50
#define XK_End 0xFF57
#define XK_Delete 0xFFFF

int VkToRimeKeysym(WPARAM vk, bool shift, bool capital) {
  if (vk >= 'A' && vk <= 'Z') {
    bool upper = shift ^ capital;
    return upper ? (int)vk : (int)vk + 32;  // 'A'/'a'
  }
  if (vk >= '0' && vk <= '9' && !shift) return (int)vk;
  switch (vk) {
    case VK_SPACE: return 0x20;
    case VK_RETURN: return XK_Return;
    case VK_BACK: return XK_BackSpace;
    case VK_ESCAPE: return XK_Escape;
    case VK_PRIOR: return XK_Prior;
    case VK_NEXT: return XK_Next;
    case VK_LEFT: return XK_Left;
    case VK_RIGHT: return XK_Right;
    case VK_UP: return XK_Up;
    case VK_DOWN: return XK_Down;
    case VK_HOME: return XK_Home;
    case VK_END: return XK_End;
    case VK_DELETE: return XK_Delete;
    case VK_OEM_MINUS: return shift ? '_' : '-';
    case VK_OEM_PLUS: return shift ? '+' : '=';
    case VK_OEM_COMMA: return shift ? '<' : ',';
    case VK_OEM_PERIOD: return shift ? '>' : '.';
    case VK_OEM_1: return shift ? ':' : ';';
    case VK_OEM_2: return shift ? '?' : '/';
    case VK_OEM_3: return shift ? '~' : '`';
    case VK_OEM_4: return shift ? '{' : '[';
    case VK_OEM_5: return shift ? '|' : '\\';
    case VK_OEM_6: return shift ? '}' : ']';
    case VK_OEM_7: return shift ? '"' : '\'';
  }
  return 0;
}
