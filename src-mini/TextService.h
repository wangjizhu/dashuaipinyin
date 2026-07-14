// 大帅拼音·极简 - TSF 文本服务
#pragma once
#include <msctf.h>
#include <windows.h>
#include "RimeEngine.h"

extern HINSTANCE g_hInst;
extern LONG g_dllRefCount;

class CTextService : public ITfTextInputProcessor,
                     public ITfKeyEventSink,
                     public ITfCompositionSink,
                     public ITfDisplayAttributeProvider,
                     public ITfCompartmentEventSink {
 public:
  CTextService();

  // IUnknown
  STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
  STDMETHODIMP_(ULONG) AddRef() override;
  STDMETHODIMP_(ULONG) Release() override;

  // ITfTextInputProcessor
  STDMETHODIMP Activate(ITfThreadMgr* ptim, TfClientId tid) override;
  STDMETHODIMP Deactivate() override;

  // ITfKeyEventSink
  STDMETHODIMP OnSetFocus(BOOL fForeground) override;
  STDMETHODIMP OnTestKeyDown(ITfContext* pic, WPARAM wp, LPARAM lp, BOOL* pfEaten) override;
  STDMETHODIMP OnTestKeyUp(ITfContext* pic, WPARAM wp, LPARAM lp, BOOL* pfEaten) override;
  STDMETHODIMP OnKeyDown(ITfContext* pic, WPARAM wp, LPARAM lp, BOOL* pfEaten) override;
  STDMETHODIMP OnKeyUp(ITfContext* pic, WPARAM wp, LPARAM lp, BOOL* pfEaten) override;
  STDMETHODIMP OnPreservedKey(ITfContext* pic, REFGUID rguid, BOOL* pfEaten) override;

  // ITfCompositionSink
  STDMETHODIMP OnCompositionTerminated(TfEditCookie ecWrite, ITfComposition* pComposition) override;

  // ITfDisplayAttributeProvider
  STDMETHODIMP EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** ppEnum) override;
  STDMETHODIMP GetDisplayAttributeInfo(REFGUID guid, ITfDisplayAttributeInfo** ppInfo) override;

  // ITfCompartmentEventSink（任务栏 中/英 点击同步）
  STDMETHODIMP OnChange(REFGUID rguid) override;

  // 内部：供编辑会话调用
  ITfComposition* composition() { return composition_; }
  void set_composition(ITfComposition* c) { composition_ = c; }
  TfClientId client_id() { return clientId_; }
  TfGuidAtom input_attr_atom() { return inputAttrAtom_; }

  // 把引擎状态应用到文档（组合串/上屏/候选窗）
  void ApplyState(ITfContext* pic, const MiniState& state);

 private:
  bool WantKey(WPARAM wp, bool composing);
  void EndCompositionIfAny(ITfContext* pic);
  // 中/英切换：更新引擎 + 任务栏指示器
  void SwitchAscii(bool ascii);
  // 写系统 InputMode Compartment（任务栏 中/英 角标）
  void SetInputModeCompartment(bool chineseMode);

  LONG refCount_;
  ITfThreadMgr* threadMgr_ = nullptr;
  TfClientId clientId_ = TF_CLIENTID_NULL;
  ITfComposition* composition_ = nullptr;
  TfGuidAtom inputAttrAtom_ = TF_INVALID_GUIDATOM;
  bool shiftArmed_ = false;        // Shift 按下且无其他键插入 → 松开时切中英
  ITfCompartment* inputModeCompartment_ = nullptr;
  DWORD compartmentSinkCookie_ = 0;
  bool settingCompartment_ = false;  // 防自触发回环
};
