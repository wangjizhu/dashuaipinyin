// 极简候选窗：置顶无焦点弹窗，GDI 横排绘制
#pragma once
#include <windows.h>
#include <string>
#include <vector>
#include "RimeEngine.h"

class CandidateWindow {
 public:
  static CandidateWindow& Instance();
  void Update(const MiniState& state, const RECT& caretRect);
  void Hide();

 private:
  CandidateWindow() = default;
  void EnsureWindow();
  void Paint(HDC dc, const RECT& rc);
  static LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);

  HWND hwnd_ = nullptr;
  MiniState state_;
  HFONT font_ = nullptr;
  HFONT labelFont_ = nullptr;
};
