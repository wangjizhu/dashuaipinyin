// 大帅拼音·极简 - DLL 入口 / COM 工厂 / 注册
#include <msctf.h>
#include <windows.h>
#include <olectl.h>
#include <string>
#include "TextService.h"
#include "guids.h"

HINSTANCE g_hInst = nullptr;
LONG g_dllRefCount = 0;

// ---------------- 类工厂 ----------------
class CClassFactory : public IClassFactory {
 public:
  STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
    if (!ppv) return E_INVALIDARG;
    if (IsEqualIID(riid, IID_IUnknown) || IsEqualIID(riid, IID_IClassFactory)) {
      *ppv = (IClassFactory*)this;
      AddRef();
      return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return 2; }   // 静态单例
  STDMETHODIMP_(ULONG) Release() override { return 1; }

  STDMETHODIMP CreateInstance(IUnknown* pUnkOuter, REFIID riid, void** ppv) override {
    if (pUnkOuter) return CLASS_E_NOAGGREGATION;
    CTextService* svc = new CTextService();
    HRESULT hr = svc->QueryInterface(riid, ppv);
    svc->Release();
    return hr;
  }
  STDMETHODIMP LockServer(BOOL fLock) override {
    if (fLock) InterlockedIncrement(&g_dllRefCount);
    else InterlockedDecrement(&g_dllRefCount);
    return S_OK;
  }
};

static CClassFactory g_factory;

BOOL WINAPI DllMain(HINSTANCE hInst, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    g_hInst = hInst;
    DisableThreadLibraryCalls(hInst);
  }
  return TRUE;
}

STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, void** ppv) {
  if (IsEqualCLSID(rclsid, CLSID_DashuaiMini))
    return g_factory.QueryInterface(riid, ppv);
  *ppv = nullptr;
  return CLASS_E_CLASSNOTAVAILABLE;
}

STDAPI DllCanUnloadNow() {
  return g_dllRefCount <= 0 ? S_OK : S_FALSE;
}

// ---------------- 注册 ----------------
static std::wstring ModulePath() {
  wchar_t path[MAX_PATH];
  GetModuleFileNameW(g_hInst, path, MAX_PATH);
  return path;
}

static LONG SetRegValue(HKEY root, const wchar_t* key, const wchar_t* name,
                        const wchar_t* value) {
  HKEY hkey;
  LONG r = RegCreateKeyExW(root, key, 0, nullptr, 0, KEY_WRITE, nullptr, &hkey, nullptr);
  if (r != ERROR_SUCCESS) return r;
  r = RegSetValueExW(hkey, name, 0, REG_SZ, (const BYTE*)value,
                     (DWORD)((wcslen(value) + 1) * sizeof(wchar_t)));
  RegCloseKey(hkey);
  return r;
}

static std::wstring GuidToString(REFGUID guid) {
  wchar_t buf[64];
  StringFromGUID2(guid, buf, 64);
  return buf;
}

STDAPI DllRegisterServer() {
  std::wstring clsid = GuidToString(CLSID_DashuaiMini);
  std::wstring path = ModulePath();
  std::wstring key = L"CLSID\\" + clsid;
  if (SetRegValue(HKEY_CLASSES_ROOT, key.c_str(), nullptr, MINI_DESC) != ERROR_SUCCESS)
    return SELFREG_E_CLASS;
  std::wstring inproc = key + L"\\InProcServer32";
  if (SetRegValue(HKEY_CLASSES_ROOT, inproc.c_str(), nullptr, path.c_str()) != ERROR_SUCCESS)
    return SELFREG_E_CLASS;
  if (SetRegValue(HKEY_CLASSES_ROOT, inproc.c_str(), L"ThreadingModel", MINI_MODEL) != ERROR_SUCCESS)
    return SELFREG_E_CLASS;

  bool coInit = SUCCEEDED(CoInitialize(nullptr));
  HRESULT hr = E_FAIL;
  {
    ITfInputProcessorProfileMgr* profileMgr = nullptr;
    hr = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr, CLSCTX_INPROC_SERVER,
                          IID_ITfInputProcessorProfileMgr, (void**)&profileMgr);
    if (SUCCEEDED(hr)) {
      hr = profileMgr->RegisterProfile(
          CLSID_DashuaiMini, MINI_LANGID, GUID_MiniProfile, MINI_DESC,
          (ULONG)wcslen(MINI_DESC), path.c_str(), (ULONG)path.size(),
          0 /* 零基图标索引：DLL 首个图标 = 帅字（与 weasel 同约定） */,
          nullptr, 0, TRUE, 0);
      profileMgr->Release();
    }
    if (SUCCEEDED(hr)) {
      ITfCategoryMgr* catMgr = nullptr;
      hr = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER,
                            IID_ITfCategoryMgr, (void**)&catMgr);
      if (SUCCEEDED(hr)) {
        const GUID* cats[] = {
            &GUID_TFCAT_TIP_KEYBOARD,
            &GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,
            &GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT,
            &GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER,
            &GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT_MINI,  // 任务栏 中/英 指示
        };
        for (auto cat : cats) {
          catMgr->RegisterCategory(CLSID_DashuaiMini, *cat, CLSID_DashuaiMini);
        }
        catMgr->Release();
      }
    }
  }
  if (coInit) CoUninitialize();
  return SUCCEEDED(hr) ? S_OK : SELFREG_E_CLASS;
}

STDAPI DllUnregisterServer() {
  bool coInit = SUCCEEDED(CoInitialize(nullptr));
  {
    ITfInputProcessorProfileMgr* profileMgr = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_ITfInputProcessorProfileMgr,
                                   (void**)&profileMgr))) {
      profileMgr->UnregisterProfile(CLSID_DashuaiMini, MINI_LANGID, GUID_MiniProfile, 0);
      profileMgr->Release();
    }
    ITfCategoryMgr* catMgr = nullptr;
    if (SUCCEEDED(CoCreateInstance(CLSID_TF_CategoryMgr, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_ITfCategoryMgr, (void**)&catMgr))) {
      const GUID* cats[] = {
          &GUID_TFCAT_TIP_KEYBOARD,
          &GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,
          &GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT,
          &GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER,
          &GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT_MINI,
      };
      for (auto cat : cats) {
        catMgr->UnregisterCategory(CLSID_DashuaiMini, *cat, CLSID_DashuaiMini);
      }
      catMgr->Release();
    }
  }
  if (coInit) CoUninitialize();

  std::wstring clsid = GuidToString(CLSID_DashuaiMini);
  std::wstring key = L"CLSID\\" + clsid;
  RegDeleteTreeW(HKEY_CLASSES_ROOT, key.c_str());
  return S_OK;
}
