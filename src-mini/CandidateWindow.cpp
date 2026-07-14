#include "CandidateWindow.h"

static const wchar_t kClsName[] = L"DashuaiMiniCandidateWnd";
static const COLORREF kBg = RGB(255, 255, 255);
static const COLORREF kBorder = RGB(210, 214, 220);
static const COLORREF kText = RGB(30, 30, 30);
static const COLORREF kLabel = RGB(140, 145, 155);
static const COLORREF kHiBg = RGB(43, 91, 215);
static const COLORREF kHiText = RGB(255, 255, 255);
static const COLORREF kPreedit = RGB(43, 91, 215);
static const int kPad = 8;
static const int kItemGap = 14;
static const int kFontPt = 16;

CandidateWindow& CandidateWindow::Instance() {
  static CandidateWindow inst;
  return inst;
}

void CandidateWindow::EnsureWindow() {
  if (hwnd_) return;
  HINSTANCE hInst = GetModuleHandleW(nullptr);
  WNDCLASSW wc = {};
  wc.lpfnWndProc = WndProc;
  wc.hInstance = hInst;
  wc.lpszClassName = kClsName;
  wc.hbrBackground = nullptr;
  wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
  RegisterClassW(&wc);  // 重复注册失败无妨
  hwnd_ = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
      kClsName, L"", WS_POPUP, 0, 0, 10, 10, nullptr, nullptr, hInst, this);
  int dpi = 96;
  HDC dc = GetDC(hwnd_);
  dpi = GetDeviceCaps(dc, LOGPIXELSY);
  ReleaseDC(hwnd_, dc);
  int h = -MulDiv(kFontPt, dpi, 72);
  font_ = CreateFontW(h, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0,
                      CLEARTYPE_QUALITY, 0, L"Microsoft YaHei");
  labelFont_ = CreateFontW(MulDiv(h, 8, 10), 0, 0, 0, FW_NORMAL, 0, 0, 0,
                           DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0,
                           L"Microsoft YaHei");
}

LRESULT CALLBACK CandidateWindow::WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  if (msg == WM_NCCREATE) {
    SetWindowLongPtrW(hwnd, GWLP_USERDATA,
                      (LONG_PTR)((CREATESTRUCTW*)lp)->lpCreateParams);
  }
  auto self = (CandidateWindow*)GetWindowLongPtrW(hwnd, GWLP_USERDATA);
  switch (msg) {
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC dc = BeginPaint(hwnd, &ps);
      RECT rc;
      GetClientRect(hwnd, &rc);
      if (self) self->Paint(dc, rc);
      EndPaint(hwnd, &ps);
      return 0;
    }
    case WM_MOUSEACTIVATE:
      return MA_NOACTIVATE;
  }
  return DefWindowProcW(hwnd, msg, wp, lp);
}

void CandidateWindow::Paint(HDC dc, const RECT& rc) {
  HBRUSH bg = CreateSolidBrush(kBg);
  FillRect(dc, &rc, bg);
  DeleteObject(bg);
  HPEN pen = CreatePen(PS_SOLID, 1, kBorder);
  HGDIOBJ oldPen = SelectObject(dc, pen);
  HGDIOBJ oldBrush = SelectObject(dc, GetStockObject(NULL_BRUSH));
  Rectangle(dc, rc.left, rc.top, rc.right, rc.bottom);
  SelectObject(dc, oldBrush);
  SelectObject(dc, oldPen);
  DeleteObject(pen);

  SetBkMode(dc, TRANSPARENT);
  int x = kPad;
  // 第一行：preedit
  SelectObject(dc, font_);
  SetTextColor(dc, kPreedit);
  TextOutW(dc, x, kPad, state_.preedit.c_str(), (int)state_.preedit.size());
  SIZE pe;
  GetTextExtentPoint32W(dc, state_.preedit.c_str(), (int)state_.preedit.size(), &pe);
  int y2 = kPad + pe.cy + 6;

  // 第二行：候选
  for (size_t i = 0; i < state_.candidates.size(); ++i) {
    std::wstring label = std::to_wstring(i + 1) + L".";
    std::wstring text = state_.candidates[i].text;
    SelectObject(dc, labelFont_);
    SIZE ls;
    GetTextExtentPoint32W(dc, label.c_str(), (int)label.size(), &ls);
    SelectObject(dc, font_);
    SIZE ts;
    GetTextExtentPoint32W(dc, text.c_str(), (int)text.size(), &ts);

    bool hi = ((int)i == state_.highlighted);
    if (hi) {
      RECT hr = {x - 4, y2 - 2, x + ls.cx + 4 + ts.cx + 4, y2 + ts.cy + 2};
      HBRUSH hb = CreateSolidBrush(kHiBg);
      FillRect(dc, &hr, hb);
      DeleteObject(hb);
    }
    SelectObject(dc, labelFont_);
    SetTextColor(dc, hi ? kHiText : kLabel);
    TextOutW(dc, x, y2 + (ts.cy - ls.cy), label.c_str(), (int)label.size());
    x += ls.cx + 4;
    SelectObject(dc, font_);
    SetTextColor(dc, hi ? kHiText : kText);
    TextOutW(dc, x, y2, text.c_str(), (int)text.size());
    x += ts.cx + kItemGap;
  }
}

void CandidateWindow::Update(const MiniState& state, const RECT& caretRect) {
  EnsureWindow();
  state_ = state;
  if (!state.composing || state.preedit.empty()) {
    Hide();
    return;
  }
  // 量尺寸
  HDC dc = GetDC(hwnd_);
  SelectObject(dc, font_);
  SIZE pe;
  GetTextExtentPoint32W(dc, state_.preedit.c_str(), (int)state_.preedit.size(), &pe);
  int w = pe.cx, lineH = pe.cy;
  int candW = 0, candH = 0;
  for (size_t i = 0; i < state_.candidates.size(); ++i) {
    std::wstring s = std::to_wstring(i + 1) + L"." + state_.candidates[i].text;
    SIZE ts;
    GetTextExtentPoint32W(dc, s.c_str(), (int)s.size(), &ts);
    candW += ts.cx + kItemGap;
    if (ts.cy > candH) candH = ts.cy;
  }
  ReleaseDC(hwnd_, dc);
  if (candW > w) w = candW;
  int width = w + kPad * 2;
  int height = kPad * 2 + lineH + 6 + candH + 2;

  int px = caretRect.left, py = caretRect.bottom + 4;
  // 防出屏
  HMONITOR mon = MonitorFromRect(&caretRect, MONITOR_DEFAULTTONEAREST);
  MONITORINFO mi = {sizeof(mi)};
  GetMonitorInfoW(mon, &mi);
  if (px + width > mi.rcWork.right) px = mi.rcWork.right - width;
  if (py + height > mi.rcWork.bottom) py = caretRect.top - height - 4;
  if (px < mi.rcWork.left) px = mi.rcWork.left;
  if (py < mi.rcWork.top) py = mi.rcWork.top;

  SetWindowPos(hwnd_, HWND_TOPMOST, px, py, width, height,
               SWP_NOACTIVATE | SWP_SHOWWINDOW);
  InvalidateRect(hwnd_, nullptr, TRUE);
}

void CandidateWindow::Hide() {
  if (hwnd_) ShowWindow(hwnd_, SW_HIDE);
}
