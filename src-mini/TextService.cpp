#include "TextService.h"
#include "CandidateWindow.h"
#include "guids.h"

// ============================================================
// 编辑会话：把引擎状态写入文档（同步执行）
// ============================================================
class CStateEditSession : public ITfEditSession {
 public:
  CStateEditSession(CTextService* svc, ITfContext* pic, const MiniState& state)
      : ref_(1), svc_(svc), pic_(pic), state_(state) {
    pic_->AddRef();
  }
  ~CStateEditSession() { pic_->Release(); }

  STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
    if (!ppv) return E_INVALIDARG;
    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfEditSession)) {
      *ppv = (ITfEditSession*)this;
      AddRef();
      return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return InterlockedIncrement(&ref_); }
  STDMETHODIMP_(ULONG) Release() override {
    ULONG r = InterlockedDecrement(&ref_);
    if (!r) delete this;
    return r;
  }

  STDMETHODIMP DoEditSession(TfEditCookie ec) override {
    // 1) 上屏文本
    if (!state_.commit.empty()) {
      CommitText(ec, state_.commit);
    }
    // 2) 组合串
    if (state_.composing && !state_.preedit.empty()) {
      UpdateComposition(ec, state_.preedit);
      UpdateCandidateWindow(ec);
    } else {
      ClearComposition(ec);
      CandidateWindow::Instance().Hide();
    }
    return S_OK;
  }

 private:
  void EnsureComposition(TfEditCookie ec) {
    if (svc_->composition()) return;
    ITfInsertAtSelection* pias = nullptr;
    if (FAILED(pic_->QueryInterface(IID_ITfInsertAtSelection, (void**)&pias)))
      return;
    ITfRange* range = nullptr;
    if (SUCCEEDED(pias->InsertTextAtSelection(ec, TF_IAS_QUERYONLY, nullptr, 0, &range)) && range) {
      ITfContextComposition* pcc = nullptr;
      if (SUCCEEDED(pic_->QueryInterface(IID_ITfContextComposition, (void**)&pcc))) {
        ITfComposition* comp = nullptr;
        if (SUCCEEDED(pcc->StartComposition(ec, range, (ITfCompositionSink*)svc_, &comp)) && comp) {
          svc_->set_composition(comp);
        }
        pcc->Release();
      }
      range->Release();
    }
    pias->Release();
  }

  void UpdateComposition(TfEditCookie ec, const std::wstring& text) {
    EnsureComposition(ec);
    ITfComposition* comp = svc_->composition();
    if (!comp) return;
    ITfRange* range = nullptr;
    if (FAILED(comp->GetRange(&range)) || !range) return;
    range->SetText(ec, 0, text.c_str(), (LONG)text.size());
    // 下划线显示属性
    ITfProperty* prop = nullptr;
    if (SUCCEEDED(pic_->GetProperty(GUID_PROP_ATTRIBUTE, &prop)) && prop) {
      VARIANT var;
      var.vt = VT_I4;
      var.lVal = svc_->input_attr_atom();
      prop->SetValue(ec, range, &var);
      prop->Release();
    }
    // 光标移到组合串末尾
    ITfRange* end = nullptr;
    if (SUCCEEDED(range->Clone(&end)) && end) {
      end->Collapse(ec, TF_ANCHOR_END);
      TF_SELECTION sel;
      sel.range = end;
      sel.style.ase = TF_AE_NONE;
      sel.style.fInterimChar = FALSE;
      pic_->SetSelection(ec, 1, &sel);
      end->Release();
    }
    range->Release();
  }

  void CommitText(TfEditCookie ec, const std::wstring& text) {
    ITfComposition* comp = svc_->composition();
    if (comp) {
      ITfRange* range = nullptr;
      if (SUCCEEDED(comp->GetRange(&range)) && range) {
        range->SetText(ec, 0, text.c_str(), (LONG)text.size());
        range->Collapse(ec, TF_ANCHOR_END);
        TF_SELECTION sel;
        sel.range = range;
        sel.style.ase = TF_AE_NONE;
        sel.style.fInterimChar = FALSE;
        pic_->SetSelection(ec, 1, &sel);
        range->Release();
      }
      comp->EndComposition(ec);
      comp->Release();
      svc_->set_composition(nullptr);
    } else {
      ITfInsertAtSelection* pias = nullptr;
      if (SUCCEEDED(pic_->QueryInterface(IID_ITfInsertAtSelection, (void**)&pias))) {
        ITfRange* range = nullptr;
        pias->InsertTextAtSelection(ec, 0, text.c_str(), (LONG)text.size(), &range);
        if (range) range->Release();
        pias->Release();
      }
    }
  }

  void ClearComposition(TfEditCookie ec) {
    ITfComposition* comp = svc_->composition();
    if (!comp) return;
    ITfRange* range = nullptr;
    if (SUCCEEDED(comp->GetRange(&range)) && range) {
      range->SetText(ec, 0, L"", 0);
      range->Release();
    }
    comp->EndComposition(ec);
    comp->Release();
    svc_->set_composition(nullptr);
  }

  void UpdateCandidateWindow(TfEditCookie ec) {
    RECT rc = {0, 0, 0, 0};
    ITfComposition* comp = svc_->composition();
    ITfContextView* view = nullptr;
    if (comp && SUCCEEDED(pic_->GetActiveView(&view)) && view) {
      ITfRange* range = nullptr;
      if (SUCCEEDED(comp->GetRange(&range)) && range) {
        BOOL clipped = FALSE;
        view->GetTextExt(ec, range, &rc, &clipped);
        range->Release();
      }
      view->Release();
    }
    if (rc.right == 0 && rc.bottom == 0) {
      POINT pt;
      GetCaretPos(&pt);
      HWND focus = GetFocus();
      if (focus) ClientToScreen(focus, &pt);
      rc.left = pt.x; rc.top = pt.y; rc.right = pt.x; rc.bottom = pt.y + 20;
    }
    CandidateWindow::Instance().Update(state_, rc);
  }

  LONG ref_;
  CTextService* svc_;
  ITfContext* pic_;
  MiniState state_;
};

// ============================================================
// 显示属性（组合串下划线）
// ============================================================
class CDisplayAttributeInfo : public ITfDisplayAttributeInfo {
 public:
  CDisplayAttributeInfo() : ref_(1) {}
  STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
    if (!ppv) return E_INVALIDARG;
    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfDisplayAttributeInfo)) {
      *ppv = (ITfDisplayAttributeInfo*)this;
      AddRef();
      return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return InterlockedIncrement(&ref_); }
  STDMETHODIMP_(ULONG) Release() override {
    ULONG r = InterlockedDecrement(&ref_);
    if (!r) delete this;
    return r;
  }
  STDMETHODIMP GetGUID(GUID* pguid) override {
    *pguid = GUID_MiniDisplayAttrInput;
    return S_OK;
  }
  STDMETHODIMP GetDescription(BSTR* pbstrDesc) override {
    *pbstrDesc = SysAllocString(L"DashuaiMini Input");
    return S_OK;
  }
  STDMETHODIMP GetAttributeInfo(TF_DISPLAYATTRIBUTE* pda) override {
    ZeroMemory(pda, sizeof(*pda));
    pda->lsStyle = TF_LS_DOT;
    pda->fBoldLine = FALSE;
    pda->crLine.type = TF_CT_NONE;
    pda->bAttr = TF_ATTR_INPUT;
    pda->crText.type = TF_CT_NONE;
    pda->crBk.type = TF_CT_NONE;
    return S_OK;
  }
  STDMETHODIMP SetAttributeInfo(const TF_DISPLAYATTRIBUTE*) override { return E_NOTIMPL; }
  STDMETHODIMP Reset() override { return S_OK; }

 private:
  LONG ref_;
};

class CEnumDisplayAttributeInfo : public IEnumTfDisplayAttributeInfo {
 public:
  CEnumDisplayAttributeInfo() : ref_(1), index_(0) {}
  STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
    if (!ppv) return E_INVALIDARG;
    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IEnumTfDisplayAttributeInfo)) {
      *ppv = (IEnumTfDisplayAttributeInfo*)this;
      AddRef();
      return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return InterlockedIncrement(&ref_); }
  STDMETHODIMP_(ULONG) Release() override {
    ULONG r = InterlockedDecrement(&ref_);
    if (!r) delete this;
    return r;
  }
  STDMETHODIMP Clone(IEnumTfDisplayAttributeInfo** ppEnum) override {
    auto e = new CEnumDisplayAttributeInfo();
    e->index_ = index_;
    *ppEnum = e;
    return S_OK;
  }
  STDMETHODIMP Next(ULONG ulCount, ITfDisplayAttributeInfo** rgInfo, ULONG* pcFetched) override {
    ULONG fetched = 0;
    if (index_ == 0 && ulCount > 0) {
      rgInfo[0] = new CDisplayAttributeInfo();
      fetched = 1;
      index_ = 1;
    }
    if (pcFetched) *pcFetched = fetched;
    return fetched == ulCount ? S_OK : S_FALSE;
  }
  STDMETHODIMP Reset() override {
    index_ = 0;
    return S_OK;
  }
  STDMETHODIMP Skip(ULONG ulCount) override {
    index_ += ulCount;
    return S_OK;
  }

 private:
  LONG ref_;
  ULONG index_;
};

// ============================================================
// CTextService
// ============================================================
CTextService::CTextService() : refCount_(1) {
  InterlockedIncrement(&g_dllRefCount);
}

STDMETHODIMP CTextService::QueryInterface(REFIID riid, void** ppv) {
  if (!ppv) return E_INVALIDARG;
  *ppv = nullptr;
  if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_ITfTextInputProcessor))
    *ppv = (ITfTextInputProcessor*)this;
  else if (IsEqualIID(riid, IID_ITfKeyEventSink))
    *ppv = (ITfKeyEventSink*)this;
  else if (IsEqualIID(riid, IID_ITfCompositionSink))
    *ppv = (ITfCompositionSink*)this;
  else if (IsEqualIID(riid, IID_ITfDisplayAttributeProvider))
    *ppv = (ITfDisplayAttributeProvider*)this;
  if (*ppv) {
    AddRef();
    return S_OK;
  }
  return E_NOINTERFACE;
}

STDMETHODIMP_(ULONG) CTextService::AddRef() { return InterlockedIncrement(&refCount_); }
STDMETHODIMP_(ULONG) CTextService::Release() {
  ULONG r = InterlockedDecrement(&refCount_);
  if (!r) {
    InterlockedDecrement(&g_dllRefCount);
    delete this;
  }
  return r;
}

STDMETHODIMP CTextService::Activate(ITfThreadMgr* ptim, TfClientId tid) {
  threadMgr_ = ptim;
  threadMgr_->AddRef();
  clientId_ = tid;

  // 注册显示属性 GUID
  ITfCategoryMgr* catMgr = nullptr;
  if (SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER,
                                 IID_ITfCategoryMgr, (void**)&catMgr))) {
    catMgr->RegisterGUID(GUID_MiniDisplayAttrInput, &inputAttrAtom_);
    catMgr->Release();
  }

  ITfKeystrokeMgr* keyMgr = nullptr;
  if (SUCCEEDED(threadMgr_->QueryInterface(IID_ITfKeystrokeMgr, (void**)&keyMgr))) {
    keyMgr->AdviseKeyEventSink(clientId_, (ITfKeyEventSink*)this, TRUE);
    keyMgr->Release();
  }

  RimeEngine::Instance().EnsureInit(g_hInst);
  return S_OK;
}

STDMETHODIMP CTextService::Deactivate() {
  CandidateWindow::Instance().Hide();
  if (threadMgr_) {
    ITfKeystrokeMgr* keyMgr = nullptr;
    if (SUCCEEDED(threadMgr_->QueryInterface(IID_ITfKeystrokeMgr, (void**)&keyMgr))) {
      keyMgr->UnadviseKeyEventSink(clientId_);
      keyMgr->Release();
    }
    threadMgr_->Release();
    threadMgr_ = nullptr;
  }
  if (composition_) {
    composition_->Release();
    composition_ = nullptr;
  }
  clientId_ = TF_CLIENTID_NULL;
  return S_OK;
}

STDMETHODIMP CTextService::OnSetFocus(BOOL fForeground) {
  if (!fForeground) CandidateWindow::Instance().Hide();
  return S_OK;
}

bool CTextService::WantKey(WPARAM wp, bool composing) {
  if (GetKeyState(VK_CONTROL) & 0x8000) return false;
  if (GetKeyState(VK_MENU) & 0x8000) return false;
  auto& engine = RimeEngine::Instance();
  if (!engine.EnsureInit(g_hInst)) return false;
  if (engine.GetAsciiMode()) return false;
  if (wp >= 'A' && wp <= 'Z') return true;
  if (!composing) return false;
  if (wp >= '0' && wp <= '9') return true;
  switch (wp) {
    case VK_SPACE: case VK_RETURN: case VK_BACK: case VK_ESCAPE:
    case VK_PRIOR: case VK_NEXT: case VK_LEFT: case VK_RIGHT:
    case VK_UP: case VK_DOWN: case VK_HOME: case VK_END: case VK_DELETE:
    case VK_OEM_MINUS: case VK_OEM_PLUS: case VK_OEM_COMMA: case VK_OEM_PERIOD:
    case VK_OEM_1: case VK_OEM_2: case VK_OEM_3: case VK_OEM_4:
    case VK_OEM_5: case VK_OEM_6: case VK_OEM_7:
      return true;
  }
  return false;
}

STDMETHODIMP CTextService::OnTestKeyDown(ITfContext* pic, WPARAM wp, LPARAM lp, BOOL* pfEaten) {
  *pfEaten = WantKey(wp, RimeEngine::Instance().IsComposing()) ? TRUE : FALSE;
  return S_OK;
}

STDMETHODIMP CTextService::OnTestKeyUp(ITfContext* pic, WPARAM wp, LPARAM lp, BOOL* pfEaten) {
  *pfEaten = FALSE;
  return S_OK;
}

STDMETHODIMP CTextService::OnKeyDown(ITfContext* pic, WPARAM wp, LPARAM lp, BOOL* pfEaten) {
  *pfEaten = FALSE;
  auto& engine = RimeEngine::Instance();
  bool composing = engine.IsComposing();

  // Shift 单击切中英：按下 Shift 且无其他键 → 候选切换在 KeyUp 执行
  if (wp == VK_SHIFT) {
    shiftPending_ = !composing;
    return S_OK;
  }
  shiftPending_ = false;

  if (!WantKey(wp, composing)) return S_OK;

  bool shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
  bool capital = (GetKeyState(VK_CAPITAL) & 1) != 0;
  int keysym = VkToRimeKeysym(wp, shift, capital);
  if (!keysym) return S_OK;

  MiniState state;
  bool handled = engine.ProcessKey(keysym, 0, state);
  if (!handled && !composing) return S_OK;  // 引擎不要，放行

  *pfEaten = TRUE;
  ApplyState(pic, state);
  return S_OK;
}

STDMETHODIMP CTextService::OnKeyUp(ITfContext* pic, WPARAM wp, LPARAM lp, BOOL* pfEaten) {
  *pfEaten = FALSE;
  if (wp == VK_SHIFT && shiftPending_) {
    shiftPending_ = false;
    RimeEngine::Instance().ToggleAsciiMode();
  }
  return S_OK;
}

STDMETHODIMP CTextService::OnPreservedKey(ITfContext* pic, REFGUID rguid, BOOL* pfEaten) {
  *pfEaten = FALSE;
  return S_OK;
}

STDMETHODIMP CTextService::OnCompositionTerminated(TfEditCookie ecWrite, ITfComposition* pComposition) {
  // 宿主强制结束组合（如点击别处）
  MiniState state;
  RimeEngine::Instance().ClearComposition(state);
  if (composition_) {
    composition_->Release();
    composition_ = nullptr;
  }
  CandidateWindow::Instance().Hide();
  return S_OK;
}

STDMETHODIMP CTextService::EnumDisplayAttributeInfo(IEnumTfDisplayAttributeInfo** ppEnum) {
  *ppEnum = new CEnumDisplayAttributeInfo();
  return S_OK;
}

STDMETHODIMP CTextService::GetDisplayAttributeInfo(REFGUID guid, ITfDisplayAttributeInfo** ppInfo) {
  if (IsEqualGUID(guid, GUID_MiniDisplayAttrInput)) {
    *ppInfo = new CDisplayAttributeInfo();
    return S_OK;
  }
  *ppInfo = nullptr;
  return E_INVALIDARG;
}

void CTextService::ApplyState(ITfContext* pic, const MiniState& state) {
  CStateEditSession* session = new CStateEditSession(this, pic, state);
  HRESULT hr = S_OK;
  pic->RequestEditSession(clientId_, session, TF_ES_SYNC | TF_ES_READWRITE, &hr);
  session->Release();
}

void CTextService::EndCompositionIfAny(ITfContext* pic) {
  if (!composition_) return;
  MiniState empty;
  ApplyState(pic, empty);
}
