# 琉璃 · QQNT 9.9.37 适配版

> 上游：[LilycleHeart/qqnt-liuli-theme](https://github.com/LilycleHeart/qqnt-liuli-theme)（`liteloader` 分支，v1.3.5）
> 这是把同一份主题适配到 **QQNT 9.9.37-54395 / Electron 40.0.0 / Node.js 24.11.1** 的修复版。

琉璃主题本体没有改动设计：MCU 壁纸取色、磨砂玻璃、TG/TIM 气泡、Markdown、@ 高亮、级联入场、布局自定义全部保留。下面的改动只解决新版 QQ 上的可用性问题。

## 适配环境

| 组件 | 版本 |
|---|---|
| QQNT | 9.9.37-54395（Windows x64） |
| Electron | 40.0.0 |
| Node.js | 24.11.1 |
| Chromium | 144.0.7559.60 |
| LiteLoaderQQNT | 1.4.1（需带 9.9.37 文件校验绕过） |

## 修复内容

### 1. 消息气泡过大

`assets/bubbles.css`

- 气泡内边距 `8px 13px` → `6px 10px`；
- 移除 `.message-container` 的 `min-height: 44px` 与 `.msg-content-container` 的 `min-height: 36px`。

这两条 `min-height` 原本是为了"头像不孤立"加的下限，但 QQ 9.9.37 的单行气泡本身有内边距，下限叠加后一行文字被撑成 44px 高的胶囊，视觉上比文字大出好几圈。

### 2. 自己的消息离头像太远

`assets/bubbles.css`

实测行上的实际间距是「grid 模板间隙 + QQ 自己的 column-gap」叠加，光改模板不够：

```css
.message-container {
  column-gap: 0 !important;       /* 关掉 QQ 自带的那份 */
}
.message-container:has(.msg-content-container.container--others) {
  grid-template-columns: 0px 32px 2px minmax(0, 1fr) 0px 0px !important;
}
.message-container:has(.msg-content-container.container--self) {
  grid-template-columns: 0px minmax(0, 1fr) 2px auto 32px 0px !important;
}
.message-container > [class*="avatar"] {
  margin-left: 0 !important;
  margin-right: 0 !important;
}
```

### 3. 悬浮窗口中，右上角窗口按钮只有下半截能点

`renderer/index.js` + `assets/layout-custom.css`

QQ 9.9.37 的窗口顶部约 36px 被它自己的 `draggable-view` 标成 `-webkit-app-region: drag`。Electron 的命中测试在 drag 区域里**不派发鼠标事件**，胶囊即使自己写了 `no-drag`，落在整块拖动区里也点不动 —— 表现就是只有最底下露出拖动区的那几像素能点。

修复：

- 胶囊展开期间（`state.l || state.r`），`syncTopDrag()` 把这些顶部拖动层临时改成内联 `-webkit-app-region: no-drag`；收起时还原为 `drag`。平时仍可拖窗口，展开时整块按钮可点；
- 胶囊 `z-index` 抬到 `99999`，每个子元素显式 `no-drag`，避免子级把父级挖出的洞又堵回去。

### 4. 未选中会话时完全没反应

`renderer/index.js` 新增 `forceNoDrag()`，`assets/layout-custom.css` 加 CSS 兜底。

空状态下 QQ 把 `.empty-panel`（1094×835）和 `.empty-panel_head`（1094×58）整块标成 `-webkit-app-region: drag`，而且是**内联 `!important`** —— 外部样式表覆盖不掉，等于整个空聊天区不接收任何鼠标事件，悬浮胶囊既唤不出也点不到。

`forceNoDrag()` 在启动时与兜底轮询里用内联 `!important` 反写这两个节点的 `-webkit-app-region`。

### 5. 性能

`renderer/index.js`

| 位置 | 原值 | 现在 |
|---|---|---|
| 路由同步 `setInterval(sync, …)` | 400ms | 1200ms |
| 全量样式/DOM 兜底 pass | 1500ms | 拆成 2s 轻活 + 8s 重活 |
| 壁纸 revision 轮询 | 1500ms | 3000ms |
| `mousemove` | 每次都执行 | `requestAnimationFrame` 节流，每帧最多一次 |
| 设置页 `refreshErrors / refreshInfo` | 3000ms | 5000ms |
| 兜底 pass 作用域 | 所有窗口（含设置页） | 仅 `data-liuli-scope="main"` |

设置页卡顿的主要来源是那套全页扫描在 `#/setting` 窗口里也照跑 —— 设置窗口本身 DOM 更重，扫描一次就掉帧。现在两个兜底定时器都先检查 `liuliScope === "main"`，设置页只剩自己的组件刷新。

原来的 1500ms 定时器每次会跑 `applyOverrides / fixContrast / normalizeColors / groupMessages / stickAvatars / markQuoteRoots / moveSenderIntoBubble / llWatchContactList / llGroupMembersPass / llMarkdownPass / llLayoutPass` 一整套全页扫描。QQ 9.9.37 的 DOM 节点数量比 9.9.36 明显更多，这套扫描是启动后持续掉帧的主要来源。

消息区的即时处理本来就有 `MutationObserver` 覆盖，定时器只做兜底，所以重活降到 8s 一次不会影响新消息的样式时机。

## 安装

1. 先把 LiteLoaderQQNT 装到 QQ 9.9.37 上（需要文件校验绕过，否则改 `package.json` 会被 `error code v2:-8` 拦下）；
2. 把本仓库整个目录放到：

```
<QQ安装目录>/versions/<版本>/resources/app/LiteLoaderQQNT/plugins/liuli-dsh-theme/
```

3. 重启 QQ，设置 → 琉璃 里配置壁纸与配色。

目录名必须是 `liuli-dsh-theme`（与 `manifest.json` 的 `slug` 一致），否则 `local://profile/plugins/<slug>/assets/` 的样式/图片会 404。

## 已知限制

- 只在 9.9.37-54395 上实测；同系列小版本大概率通用。
- 气泡与头像的 4px 间距是肉眼调的值，觉得太紧可以把 `assets/bubbles.css` 里两处 `4px` 改回 `6px/8px`。
- 顶部胶囊下移到 14px 后，视觉上离窗口上沿比原版多一点空隙；这是为了避开非客户区，换来的整块可点击。
- 空会话面板改成 `no-drag` 后，不能再用空聊天区拖动窗口，标题栏仍然可以拖。
- 主题的磨砂玻璃是整窗 `backdrop-filter: blur()`，核显/低端独显在 2K 以上窗口依然会掉帧，这是材质本身的成本，可以在 设置 → 琉璃 → 外观 里调低模糊半径。

## 上游与许可

- 设计与实现：LilycleHeart，MIT License；
- 本仓库只是针对 QQ 9.9.37 的兼容性补丁，未改变原主题的视觉设计。
