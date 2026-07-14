// 进程内 librime 封装（每个宿主进程一份）
#pragma once
#include <windows.h>
#include <string>
#include <vector>

struct MiniCandidate {
  std::wstring text;
  std::wstring comment;
};

struct MiniState {
  bool composing = false;
  std::wstring preedit;          // 组合串（带音节分隔）
  std::wstring commit;           // 本次上屏文本（空=无）
  std::vector<MiniCandidate> candidates;  // 当前页候选
  int highlighted = 0;
  int page_no = 0;
  bool is_last_page = false;
};

class RimeEngine {
 public:
  static RimeEngine& Instance();

  bool EnsureInit(HINSTANCE dllModule);
  void Finalize();
  // 配置热重载：检测 build 产物更新则重建引擎（3 秒节流，仅在非组合状态调用）
  void MaybeReload();

  // 返回 true = 按键被引擎消费；state 为处理后的最新状态
  bool ProcessKey(int keysym, int mask, MiniState& state);
  void ClearComposition(MiniState& state);
  bool IsComposing();
  bool GetAsciiMode();
  void SetAsciiMode(bool ascii);
  void ToggleAsciiMode();
  std::wstring GetRawInput();  // 组合中的原始按键串（Shift 上屏用）

 private:
  RimeEngine() = default;
  void RefreshState(MiniState& state);

  void* api_ = nullptr;      // RimeApi*
  HMODULE rimeDll_ = nullptr;
  uintptr_t session_ = 0;
  bool initialized_ = false;
  bool initFailed_ = false;
  HINSTANCE dllModule_ = nullptr;
  std::wstring buildMarker_;          // build\wanxiang.schema.yaml 路径
  FILETIME buildStamp_ = {};          // 初始化时的产物时间戳
  unsigned long long lastReloadCheck_ = 0;
};

// VK + 修饰键 → X11 keysym（librime 的按键编码）；返回 0 = 不转发
int VkToRimeKeysym(WPARAM vk, bool shift, bool capital);
