# -*- coding: utf-8 -*-
"""Engine-level typing test: simulate pinyin input via rime.dll and dump candidates."""
import ctypes, os, sys, io

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")

WEASEL = r"C:\Program Files\Rime\weasel-0.17.4"
USER_DIR = os.path.join(os.environ["APPDATA"], "Rime")
LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rime-test-logs")
os.makedirs(LOG_DIR, exist_ok=True)
os.environ["GLOG_logbufsecs"] = "0"

class RimeTraits(ctypes.Structure):
    _fields_ = [
        ("data_size", ctypes.c_int),
        ("shared_data_dir", ctypes.c_char_p),
        ("user_data_dir", ctypes.c_char_p),
        ("distribution_name", ctypes.c_char_p),
        ("distribution_code_name", ctypes.c_char_p),
        ("distribution_version", ctypes.c_char_p),
        ("app_name", ctypes.c_char_p),
        ("modules", ctypes.POINTER(ctypes.c_char_p)),
        ("min_log_level", ctypes.c_int),
        ("log_dir", ctypes.c_char_p),
        ("prebuilt_data_dir", ctypes.c_char_p),
        ("staging_dir", ctypes.c_char_p),
    ]

class RimeComposition(ctypes.Structure):
    _fields_ = [
        ("length", ctypes.c_int),
        ("cursor_pos", ctypes.c_int),
        ("sel_start", ctypes.c_int),
        ("sel_end", ctypes.c_int),
        ("preedit", ctypes.c_char_p),
    ]

class RimeCandidate(ctypes.Structure):
    _fields_ = [
        ("text", ctypes.c_char_p),
        ("comment", ctypes.c_char_p),
        ("reserved", ctypes.c_void_p),
    ]

class RimeMenu(ctypes.Structure):
    _fields_ = [
        ("page_size", ctypes.c_int),
        ("page_no", ctypes.c_int),
        ("is_last_page", ctypes.c_int),
        ("highlighted_candidate_index", ctypes.c_int),
        ("num_candidates", ctypes.c_int),
        ("candidates", ctypes.POINTER(RimeCandidate)),
        ("select_keys", ctypes.c_char_p),
    ]

class RimeContext(ctypes.Structure):
    _fields_ = [
        ("data_size", ctypes.c_int),
        ("composition", RimeComposition),
        ("menu", RimeMenu),
        ("commit_text_preview", ctypes.c_char_p),
        ("select_labels", ctypes.POINTER(ctypes.c_char_p)),
    ]

class RimeCommit(ctypes.Structure):
    _fields_ = [
        ("data_size", ctypes.c_int),
        ("text", ctypes.c_char_p),
    ]

os.add_dll_directory(WEASEL)
rime = ctypes.CDLL(os.path.join(WEASEL, "rime.dll"))

SID = ctypes.c_void_p
rime.RimeCreateSession.restype = SID
rime.RimeSimulateKeySequence.argtypes = [SID, ctypes.c_char_p]
rime.RimeGetContext.argtypes = [SID, ctypes.POINTER(RimeContext)]
rime.RimeGetCommit.argtypes = [SID, ctypes.POINTER(RimeCommit)]
rime.RimeFreeContext.argtypes = [ctypes.POINTER(RimeContext)]
rime.RimeFreeCommit.argtypes = [ctypes.POINTER(RimeCommit)]
rime.RimeClearComposition.argtypes = [SID]
rime.RimeDestroySession.argtypes = [SID]

traits = RimeTraits()
traits.data_size = ctypes.sizeof(RimeTraits) - ctypes.sizeof(ctypes.c_int)
traits.shared_data_dir = os.path.join(WEASEL, "data").encode("utf-8")
traits.user_data_dir = USER_DIR.encode("utf-8")
traits.distribution_name = b"Weasel"
traits.distribution_code_name = b"weasel"
traits.distribution_version = b"0.17.4"
traits.app_name = b"rime.weasel"
traits.min_log_level = 0
traits.log_dir = LOG_DIR.encode("utf-8")

rime.RimeSetup(ctypes.byref(traits))
rime.RimeInitialize(ctypes.byref(traits))
# no maintenance needed: workspace already deployed

sid = rime.RimeCreateSession()
print(f"session: {sid}")

TESTS = [
    "jintiantianqizhenbucuo",
    "womingtianyaoqubeijingkaihui",
    "dashuaipinyinshurufa",
    "zhegeshurufameiyouguanggao",
    "yuyanmoxingnenggoutigaozhengjuzhunquelv",
    "womenyiqichifanba",
]

for pinyin in TESTS:
    rime.RimeClearComposition(sid)
    ok = rime.RimeSimulateKeySequence(sid, pinyin.encode("ascii"))
    ctx = RimeContext()
    ctx.data_size = ctypes.sizeof(RimeContext) - ctypes.sizeof(ctypes.c_int)
    if rime.RimeGetContext(sid, ctypes.byref(ctx)):
        preedit = (ctx.composition.preedit or b"").decode("utf-8", "replace")
        cands = []
        for i in range(min(ctx.menu.num_candidates, 5)):
            c = ctx.menu.candidates[i]
            cands.append((c.text or b"").decode("utf-8", "replace"))
        print(f"{pinyin}")
        print(f"  preedit:    {preedit}")
        print(f"  candidates: {' | '.join(cands)}")
        rime.RimeFreeContext(ctypes.byref(ctx))
    # commit first candidate with space
    rime.RimeSimulateKeySequence(sid, b" ")
    commit = RimeCommit()
    commit.data_size = ctypes.sizeof(RimeCommit) - ctypes.sizeof(ctypes.c_int)
    if rime.RimeGetCommit(sid, ctypes.byref(commit)):
        print(f"  committed:  {(commit.text or b'').decode('utf-8', 'replace')}")
        rime.RimeFreeCommit(ctypes.byref(commit))
    print()

rime.RimeDestroySession(sid)
rime.RimeFinalize()
print("test done")
