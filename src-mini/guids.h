// 大帅拼音·极简 TSF 前端 - GUID 定义
// 全新 GUID，与小狼毫 (A3F4CDED-...) 完全独立，可共存、可单独卸载
#pragma once
#include <windows.h>

// {DA548A11-0714-4E22-9B0C-3F2A61C0D9E1} 文本服务 CLSID
static const CLSID CLSID_DashuaiMini = {
    0xDA548A11, 0x0714, 0x4E22, {0x9B, 0x0C, 0x3F, 0x2A, 0x61, 0xC0, 0xD9, 0xE1}};

// {DA548A12-0714-4E22-9B0C-3F2A61C0D9E2} 输入法 LanguageProfile
static const GUID GUID_MiniProfile = {
    0xDA548A12, 0x0714, 0x4E22, {0x9B, 0x0C, 0x3F, 0x2A, 0x61, 0xC0, 0xD9, 0xE2}};

// {DA548A13-0714-4E22-9B0C-3F2A61C0D9E3} 组合串显示属性（下划线）
static const GUID GUID_MiniDisplayAttrInput = {
    0xDA548A13, 0x0714, 0x4E22, {0x9B, 0x0C, 0x3F, 0x2A, 0x61, 0xC0, 0xD9, 0xE3}};

#define MINI_DESC L"大帅拼音·极简"
#define MINI_MODEL TEXT("Apartment")
#define MINI_LANGID MAKELANGID(LANG_CHINESE, SUBLANG_CHINESE_SIMPLIFIED)
