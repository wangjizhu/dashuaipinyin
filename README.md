# 大帅拼音输入法

> 高效、纯净、完全离线的 Windows 拼音输入法。

**整句智能转换 · 100% 本地运行 · 无广告 · 零联网零遥测 · 完全开源可审计**

## 设计理念

输入法只该做一件事：把拼音又快又准地变成汉字。

- **高效**：基于大规模语言模型的整句转换（32GB 语料训练的多级 n-gram），
  万象官方 22.4 万句测试集实测：整句正确率 **76.86%**，字正确率 **96.32%**。
  连打长句一次成型，自动学习你的用词习惯，越用越顺手。
- **纯净**：没有广告、没有弹窗、没有皮肤商店、没有云端账号，运行期
  **不发起任何网络请求**——词库更新完全由你手动掌控。监管部门早有明确结论：
  输入法实现基本功能根本无须收集任何个人信息。本输入法就是这句话的落地。
- **极简**：开箱即用，零配置；进阶功能全部藏在明确的引导符后面，不打扰日常打字。

## 完全开源

大帅拼音是多个活跃维护的开源项目的深度整合发行版，每一行代码可审计：

| 组件 | 项目 | 协议 | 作用 |
|---|---|---|---|
| 输入法前端 + 引擎 | [小狼毫 Weasel](https://github.com/rime/weasel)（内含 [librime](https://github.com/rime/librime)） | GPL-3.0 / BSD-3 | Windows TSF 输入法本体、候选窗、按键处理 |
| 拼音方案 + 词库 | [万象拼音 base](https://github.com/amzxyz/rime-wanxiang) | CC-BY-4.0 | 全拼方案、百万级现代词库 |
| 语言模型 | [万象语言模型 LTS](https://github.com/amzxyz/RIME-LMDG) | CC-BY-4.0 | 整句智能转换 |

本仓库的品牌化补丁（`patches/`）、定制配置（`rime-config/`）与全部构建/安装脚本
（`scripts/`）同样开源，以 GPL-3.0 发布（见 [LICENSE](LICENSE)）。

## 安装

### Windows 10 / 11

**方式一（推荐）：完整安装包**

到本仓库的 [Releases 页面](https://github.com/wangjizhu/dashuaipinyin/releases)
下载最新的 `dashuai-pinyin-<版本>-windows-x64-setup.exe`，双击安装（词库与语言模型
已全部内置，安装全程无须联网）。装完按 **Win + 空格** 切换到【大帅拼音】即可打字。

**方式二：脚本安装（自动下载各开源组件后组装）**

以管理员身份打开 PowerShell：

```powershell
cd <本仓库目录>
Set-ExecutionPolicy -Scope Process Bypass -Force
.\scripts\install.ps1
```

**卸载**：Windows 设置 → 应用 中卸载，或运行 `.\scripts\uninstall.ps1`
（加 `-PurgeUserData` 连个人词典一起清除）。

### Ubuntu 24.04 及以上

前端使用系统仓库自带的 ibus-rime（GNOME 默认，推荐）或 fcitx5-rime，
词库、语言模型与全部定制和 Windows 版**完全同源**，输入体验一致。

```bash
# 从 Releases 页面下载安装脚本后运行（会自动 apt 安装前端并下载数据包）
wget https://github.com/wangjizhu/dashuaipinyin/releases/download/v0.17.4.1/dashuai-pinyin-0.17.4.1-ubuntu-install.sh
bash dashuai-pinyin-0.17.4.1-ubuntu-install.sh            # ibus 前端（默认）
bash dashuai-pinyin-0.17.4.1-ubuntu-install.sh fcitx5     # 或改用 fcitx5 前端

# 离线安装：先下载数据包，作为第二个参数传入
bash dashuai-pinyin-0.17.4.1-ubuntu-install.sh ibus dashuai-pinyin-0.17.4.1-ubuntu-rime-data.tar.gz
```

装完注销重新登录，到 设置 → 键盘 → 输入源 添加「中文（大帅拼音）」，
Super + 空格切换即可打字，顶栏指示图标为「帅」。

> 说明：Ubuntu 22.04 及更早版本的系统 librime（1.7.3）过旧、无法运行万象方案，
> 安装脚本会明确拒绝并提示，请使用 Ubuntu 24.04+。

### Android

下载 Releases 中的 `dashuai-pinyin-<版本>-android-arm64.apk` 直接安装
（独立完整 App：应用名与图标即「大帅拼音 / 帅」，词库与语言模型全部内置）：

1. 安装 APK（需允许"未知来源应用"），打开「大帅拼音」
2. 按提示授予权限，等待首次自动部署完成（约 1-2 分钟）
3. 系统设置 → 输入法 中启用「大帅拼音」并切换使用
4. 建议在 App 主页 → 主题 中选择「简纯+」键盘布局

安卓版基于开源前端 [Trime](https://github.com/osfans/trime)（GPL-3.0）构建，
改造与构建脚本见 `scripts/android-branding.sh`、`scripts/make-android-icons.py`。
已有原版 Trime 的进阶用户也可只取 `-android-rime-data.zip` 数据包导入，
整句转换、候选排序、自定义短语与桌面版行为一致。

## 常用操作

| 按键 | 功能 |
|---|---|
| **Shift** | 中英文切换（打字打到一半按下：已输入的字母原样上屏并切到英文） |
| CapsLock | 只切大小写，不会误切输入法 |
| 空格 | 上屏首选 |
| 数字 1–9 | 选候选词 |
| 回车 | 拼音字母原样上屏（临时打英文单词很方便） |
| `-` / `=`（或 PageUp / PageDown） | 候选翻页 |
| **`'`（单引号）** | 音节分隔符。连打默认按最长音节切分（`xian` → 先）；要拆开音节就手动加分隔符（`xi'an` → 西安） |
| **Shift + Delete** | 删掉学错的词：用 ↓ 键把它高亮，再按此键（只对自动学习的词有效） |
| Ctrl + `` ` `` | 状态面板：中英标点、简繁转换等开关 |
| Tab | 光标跳到下一个音节 |
| Alt + ← / Alt + → | 按音节移动光标 |
| Ctrl + w | 从光标处删掉一个音节 |
| Ctrl + j / Ctrl + k / Ctrl + 0 | 手动排序：高亮候选往前挪 / 往后挪 / 取消手动排序 |

**关于候选词排序**：词序 = 词库基础词频 + 语言模型整句打分 + 你的使用习惯（自动调频，
常用词自动靠前）。误选过的词如果窜到前面，用 **Shift+Delete** 删掉即可恢复。

## 进阶功能（引导符触发，不打扰日常输入）

| 输入 | 功能 | 示例 |
|---|---|---|
| `/sj`、`/rq` 等 | 时间、日期、农历、节气、节日 | `/sj` → 16:21 |
| `R` + 数字 | 金额大写 | `R1234` → 壹仟贰佰叁拾肆元整 |
| `V` + 算式 | 计算器 | `V1+1` → 2 |
| `U` + 十六进制 | Unicode 查字 | `U4e2d` → 中 |
| `` ` `` + 拼音 | 部件拆分 / 笔画反查生僻字 | `` `wang `` → 瑷 璈 … |
| `/` + 字母 | 更多符号与模板（详见万象拼音文档） | |

## 词库与个性化

- **自定义短语**：编辑 `%APPDATA%\Rime\custom_phrase.txt`，
  格式为 `词语<TAB>编码<TAB>权重`（一行一条），保存后在任务栏图标右键【重新部署】。
  写在这里的词永远置顶。
- **个人词典**：`%APPDATA%\Rime` 下的 `*.userdb` 目录，记录你的输入习惯，可随时备份。
- **从其他输入法迁移词库**：先在原输入法中导出个人词库，用开源工具
  [深蓝词库转换](https://github.com/studyzy/imewlconverter) 转成 Rime 格式，
  追加到 `custom_phrase.txt` 后重新部署。注意：受版权保护的词库仅限个人本地使用，请勿分发。
- **深度定制**：把 `*.custom.yaml` 补丁文件放进 `%APPDATA%\Rime`（参考本仓库
  `rime-config/` 的写法）后重新部署。不要直接改万象自带的 yaml，更新时会被覆盖。

## 从源码构建

```powershell
.\scripts\build-dashuai.ps1     # 拉取 weasel 0.17.4 源码 + 打品牌补丁 + 全量编译
.\scripts\make-installer.ps1    # 组装数据负载（方案 + 词库 + 语言模型）→ NSIS 打完整安装包
.\scripts\deploy-dashuai.ps1    # 把构建产物部署到本机
python .\scripts\test-engine.py # 引擎级回归测试（整句转换质量验证）
```

前置要求：VS2019 Build Tools（含 C++ 工具集与 ATL）、git、NSIS。

## 项目结构

```
shurufa/
├── README.md                  本文件
├── LICENSE                    GPL-3.0
├── scripts/
│   ├── install.ps1            脚本安装（下载组件 + 部署 + 编译词库）
│   ├── uninstall.ps1          干净卸载
│   ├── build-dashuai.ps1      源码构建全套二进制
│   ├── make-installer.ps1     打完整安装包
│   ├── deploy-dashuai.ps1     构建产物部署到本机
│   ├── make-icons.py          「帅」字全套图标生成
│   └── test-engine.py         引擎级回归测试
├── patches/                   品牌化补丁（基于 weasel 0.17.4）
├── rime-config/               大帅定制配置（*.custom.yaml + lua 扩展）
├── build-out/                 构建产物（安装包不入库，发布走 Releases）
└── docs/                      技术选型调研与路线文档
```

## 协议

本仓库以 **GPL-3.0** 发布（与所含小狼毫组件保持一致），完整文本见 [LICENSE](LICENSE)。
各组件版权归其原项目所有：Weasel / librime © RIME 及贡献者；
万象拼音 / 万象语言模型 © amzxyz（CC-BY-4.0，此处署名致谢）。
