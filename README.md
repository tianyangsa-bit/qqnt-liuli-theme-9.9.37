# LiteLoaderQQNT · QQNT 9.9.37 适配版

把 [LiteLoaderQQNT](https://github.com/LiteLoaderQQNT/LiteLoaderQQNT) 1.4.1 移到 **QQNT 9.9.37-54395 / Electron 40.0.0 / Node.js 24.11.1** 上。

配套的琉璃主题适配见：[tianyangsa-bit/qqnt-liuli-theme-9.9.37](https://github.com/tianyangsa-bit/qqnt-liuli-theme-9.9.37)

## 两个拦路的东西

### 1. package.json 的 RSA 签名校验（`error code v2:-8`）

`resources/app/application.json` 给 `package.json` / `application.asar` / `wrapper.node` / `major.node` 各挂一个 256 字节 RSA-2048 签名。改 `main` 之后启动器打印：

```
ac12d1b1…（package.json 的 SHA-256）
error code v2:-8
```

进程直接退出。校验代码不在 `QQ.exe`（老版 `QQNTFileVerifyPatch` 的目标），在 **`QQNT.dll` 的 `.text` 段**：

```
0x1805116F7  mov  rsi, rcx
0x1805116F7  mov  rdx, [rcx]
0x1805116FD  mov  r8,  [rcx+8]
0x180511701  sub  r8,  rdx
0x180511704  mov  rcx, [rcx+0x18]
0x180511708  call <compare>          ← 把这一条打成 mov eax,1
0x18051170D  mov  edi, eax
…
0x18051174E  cmp  edi, 1
0x180511751  sete al
```

`QQNT.dll` 有 ACL 保护，改不了磁盘文件；`QQ.exe` 也写不了。但版本目录可写，且 `QQNT.dll` 静态导入 `VERSION.dll` —— 用同名代理 DLL，在它被加载时扫描 `.text`、内存里把 `call` 换成 `mov eax,1`。

### 2. Node 24 删掉了 `Dirent.prototype.path`

`LiteLoaderQQNT/src/main/store.js` 的 `scanPluginDirectory()`：

```js
.map(dirent => path.join(dirent.path, dirent.name, "manifest.json"))
```

Node 24 里 `dirent.path` 是 `undefined`，直接抛：

```
TypeError [ERR_INVALID_ARG_TYPE]: The "path" argument must be of type string. Received undefined
```

主进程崩在启动阶段。改成：

```js
.map(dirent => path.join(dirent.parentPath ?? dirent.path ?? LiteLoader.path.plugins, dirent.name, "manifest.json"))
```

`parentPath` 是 Node 20.12+ 的字段，保留 `dirent.path` 回退兼容旧 Node。

## version.dll 做了什么

`proxy/version_proxy.cpp`，编译产物就是仓库根目录的 `version.dll`：

1. `DllMain` 里确认 `QQNT.dll` 已映射，解析它的 PE 段表，取 `.text`；
2. 扫描 `QQNTFileVerifyPatch` 的 x64 特征码：

   ```
   48 89 CE 48 8B 11 4C 8B 41 08 49 29 D0 48 8B 49 18 E8
   ```

3. 命中后把末尾的 `E8`（`call`）原地改写成 `B8 01 00 00 00`（`mov eax,1`），`VirtualProtect` 改回原保护，`FlushInstructionCache`；
4. 三个导出 `GetFileVersionInfoSizeW` / `GetFileVersionInfoW` / `VerQueryValueW` 转发到 `System32\version.dll`，QQ 的版本查询不受影响。

只改运行时内存，磁盘上的 `QQNT.dll` 不动。日志写在 `%LOCALAPPDATA%\LiteLoaderQQNT\patch.log`：

```
[proxy] attached pid=12580
[proxy] patched verifier at ... (rva 0x5116F7)
```

特征码没找到时写 `verification signature NOT FOUND` 并放行，安装器会在安装前先扫一遍 QQNT.dll 给出警告。

## 安装

1. 完全退出 QQ（含托盘图标）。
2. 双击 `install.bat`；如果提示无写入权限，右键以管理员身份运行。
3. 启动 QQ。

安装脚本：

- 从 `versions\config.json` 的 `curVersion` 定位当前版本目录；
- 扫 `QQNT.dll` 的特征码，找不到时警告"该版本尚未适配"并让你确认；
- 备份 `package.json` → `package.json.llqqnt.bak`（只备份一次）；
- 部署 `LiteLoaderQQNT\` 到 `resources\app\`；
- `package.json` 的 `main` 改写为 `./LiteLoaderQQNT/src/main.js`，其余字段原样保留，写无 BOM UTF-8；
- 部署 `version.dll` 到 `versions\<ver>\`。

## 卸载

完全退出 QQ，双击 `uninstall.bat`：

- 从备份恢复 `package.json`（仅当它仍指向 LiteLoader）；
- 删除 `version.dll`；
- `LiteLoaderQQNT\` 改名为 `LiteLoaderQQNT.uninstalled-<时间戳>`，插件与配置保留。

## QQ 自动更新之后

hotUpdate 会解压出新的 `versions\<new-version>\` 并切换 `config.json` 的 `curVersion`。新目录里没有 `version.dll`，`package.json` 也是原版 —— 重新跑一次 `install.bat`。

如果 QQ 改了校验函数结构，安装器的特征码扫描会先报警，不会让你装完打不开。

## 自己编译 version.dll

需要 Visual Studio 2022 BuildTools（x64）：

```bat
cd proxy
build.bat
```

输出 `version.dll`，导出表：`GetFileVersionInfoSizeW`、`GetFileVersionInfoW`、`VerQueryValueW`，外加三个 `Proxy_*` 转发实现。

## 验证

- `%LOCALAPPDATA%\LiteLoaderQQNT\patch.log` 里出现 `patched verifier at ... (rva 0x5116F7)`；
- QQ 正常登录；
- 设置页左侧出现 **LiteLoaderQQNT** 标签，版本栏显示 LiteLoader 1.4.1 / QQNT 9.9.37-54395 / Electron 40.0.0 / Node.js 24.11.1。

## 已知限制

- 只在 9.9.37-54395 实测；同系列小版本大概率通用，跨大版本需要重新确认特征码。
- `version.dll` 会被每个加载 `QQNT.dll` 的进程加载并各 patch 一次，幂等。
- 改的是本机安装的 QQ 客户端的自校验，仅用于加载本地插件。
- `application.asar` 内部的 JS 是加密存储的，但 QQ 在 Node 加载器层透明解密，`require()` 拿到的是明文 —— 框架层不需要额外处理。

## 目录

```
.
├── install.bat / install.ps1        安装
├── uninstall.bat / uninstall.ps1    卸载
├── version.dll                      校验绕过代理（编译产物）
├── proxy/
│   ├── version_proxy.cpp            代理源码（签名扫描 + 内存 patch + 转发）
│   └── build.bat                    MSVC 构建
└── LiteLoaderQQNT/                  1.4.1，仅一处 Node 24 兼容修复
```

## 许可

- LiteLoaderQQNT 本体：MIT，LiteLoaderQQNT 组织；
- `version.dll` 与安装脚本：本仓库新增，MIT。
