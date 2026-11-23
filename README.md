# 琉璃 · QQNT 9.9.37 适配版

> 上游：[LilycleHeart/qqnt-liuli-theme](https://github.com/LilycleHeart/qqnt-liuli-theme)（`liteloader` 分支，v1.3.5）
> 本仓库把同一份主题适配到 **QQNT 9.9.37-54395 / Electron 40.0.0 / Node.js 24.11.1**，并针对新版 DOM 做了性能与交互修复。

设计语言没有改：MCU 壁纸取色、磨砂玻璃、TG/TIM 气泡、Markdown、@ 高亮、级联入场、布局自定义全部保留。下面的改动只解决新版 QQ 上的可用性与性能问题。

## 适配环境

| 组件 | 版本 |
|---|---|
| QQNT | 9.9.37-54395（Windows x64） |
| Electron | 40.0.0 |
| Node.js | 24.11.1 |
| Chromium | 144.0.7559.60 |
| LiteLoaderQQNT | 1.4.1（需带 9.9.37 文件校验绕过：[liteloader-qqnt-9.9.37](https://github.com/tianyangsa-bit/liteloader-qqnt-9.9.37)） |

---

# 1.3.7+qq9937

## 新增：列表滑翔高亮

原来每个列表项各自 `background` 淡入淡出：鼠标从一行移到下一行，是「上一行原地消失、下一行原地出现」。现在改成一块共享高亮跟着指针在行间平移。

| 行为 | 实现 |
|---|---|
| 同一列表内换行 | `transform` + `width/height` 连续滑动 |
| 位移时长 | 按距离给：跨一行约 240ms，跨多行封顶 280ms |
| 行间空隙 | 60ms 宽限，指针扫过 1px 行距不会闪断 |
| 跨列表（会话 → 群成员） | 直接跳位淡入，不做横跨窗口的飞行 |
| 滚动列表 | 立即隐藏，停手 140ms 后用 `elementFromPoint` 重新吸附 |
| 离开窗口 / 失焦 / 拉伸 | 立即淡出 |
| 虚拟列表回收节点 | 500ms 巡检 `isConnected`，断开即收 |
| `prefers-reduced-motion` | 关闭过渡，直接跳位 |

覆盖范围：

- 左侧消息/会话列表 `.recent-contact-item`
- 群聊群成员列表 `.group-user`（高亮落在 `.group-user__content`，与原生悬停区域一致）
- 右键菜单项 `.q-context-menu-item`
- 设置页左侧导航 `.nav-item`

实现上只用一块 `body` 级 fixed 合成层，动的只有 `transform / width / height / opacity`，不碰任何 QQ 节点，不触发列表排版。

## 修复：会话列表悬停底色仍在「原地出现 / 消失」

实测（枚举 `document.styleSheets` 得到）QQ 9.9.37 的会话悬停底色不在行元素上，而是画在：

```css
.recent-contact-item:hover .item__content[data-v-6cc45a37]::before
```

所以只清 `.recent-contact-item` 的背景没有用。现在只清**没有未读角标**的行——有角标的行上，同一个伪元素被主题画成了左缘品牌微光，动它会闪。

## 性能：模糊预算

每个 `backdrop-filter` 都是一块独立合成表面，壁纸/内容一变就要重跑一次高斯模糊。原版同时有十几层在跑。

| 表面 | 之前 | 现在 |
|---|---|---|
| 每条对方消息气泡 | `blur(12px)` × 几十个 | 无（底色本就接近不透明） |
| 群成员面板 `.group-box` | 18px，且嵌在 `.right-sidebar` 里 = 双层 | 无（外层已模糊） |
| 左栏 / 会话列表 / 右栏 / 资料卡 | 18px | 9px |
| 弹层、右键菜单 | 28px | 无，0.97 实底 |
| 输入区 / 展开功能栏 | 40px | 10px |
| 琉璃面板 / 壁纸编辑器 | 28–30px | 无，0.94–0.97 实底 |
| 设置页整窗 `.setting-layout` | 18px | 无，0.9 实底 |
| 转发卡片 | 14px | 无 |
| 独立窗口整窗 | 24px | 12px |

群聊一屏 30 条消息：约 **36 个模糊表面 → 5 个**，半径减半。

## 性能：动画

- 群成员「最近 3 位发言者」的头像呼吸是无限循环的 `box-shadow` 动画。`box-shadow` 不可合成，每帧都要重绘该行，而它就长在群成员列表里，滚动和 hover 一直在和它抢绘制 → 改成静态光环。
- 全库 `animation: ... infinite` 现在为 **0**。

## 性能：热路径

| 位置 | 问题 | 处理 |
|---|---|---|
| 侧栏 MutationObserver | 群成员列表 hover 会反复插入/删除行内节点，每批都跑一次全量扫描（遍历成员行 → 算管理块 → 回扫 60 条消息） | 250ms 节流 + 末尾补跑 |
| `fixContrast` | 只给"命中"的节点打标记，颜色正常的节点每 8 秒重新 `getComputedStyle` | `WeakSet` 记账，每个节点只判一次 |
| 消息 MutationObserver | 属性改动、空记录也会触发消息分组重算 | 只认真正的 `childList` 节点增删 |
| 路由同步 | 400ms | 1200ms |
| 全量样式的兜底 pass | 1500ms 跑一整套 | 拆成 2s 轻活 + 8s 重活 |
| 壁纸 revision 轮询 | 1500ms | 3000ms |
| 设置页 `refreshErrors / refreshInfo` | 3000ms | 5000ms |
| `mousemove` | 每次执行 | `requestAnimationFrame` 节流 |
| 兜底 pass 作用域 | 所有窗口 | 仅 `data-liuli-scope="main"` |
| 截图 / 隐藏 / blank 窗口 | 照样注入 | 直接跳过 |
| 设置页 CSS | 16 个文件 | 9 个 |

---

# 1.3.6+qq9937

## 消息气泡过大

`assets/bubbles.css`

- 气泡内边距 `8px 13px` → `6px 10px`；
- 移除 `.message-container` 的 `min-height: 44px` 与 `.msg-content-container` 的 `min-height: 36px`。

这两条 `min-height` 原本是为了「头像不孤立」加的下限，但 9.9.37 的单行气泡自带内边距，叠加后一行文字被撑成 44px 高的胶囊。

## 自己的消息离头像太远

实际间距是「grid 模板间隙 + QQ 自己的 `column-gap`」叠加：

```css
.message-container { column-gap: 0 !important; }
.message-container:has(.msg-content-container.container--others) {
  grid-template-columns: 0px 32px 2px minmax(0, 1fr) 0px 0px !important;
}
.message-container:has(.msg-content-container.container--self) {
  grid-template-columns: 0px minmax(0, 1fr) 2px auto 32px 0px !important;
}
.message-container > [class*="avatar"] { margin-left: 0 !important; margin-right: 0 !important; }
```

## 悬浮窗口里，右上角按钮只有下半截能点

9.9.37 的窗口顶部约 36px 被 QQ 标成 `-webkit-app-region: drag`。Electron 的命中测试在 drag 区**不派发鼠标事件**，胶囊自己写 `no-drag` 也没用。

- 胶囊展开期间（`state.l || state.r`），`syncTopDrag()` 把顶部拖动层临时改成内联 `no-drag`；收起时还原为 `drag`。
- 胶囊 `z-index` 抬到 `99999`，子元素显式 `no-drag`。

## 未选中会话时完全没反应

空状态下 QQ 把 `.empty-panel` 和 `.empty-panel_head` 整块标成内联 `!important` 的 drag 区，外部样式表覆盖不掉。`forceNoDrag()` 用内联 `!important` 反写，并在兜底轮询里持续纠正。

---

## 材质与配置

- 默认模糊半径 `18px → 9px`；老配置里存着的 `18`（老默认值）会在加载时迁移为 9，用户自己调过的其它数值保留。
- 参数在 **设置 → 琉璃 → 外观**：模糊、不透明度、泛光、阴影、壁纸遮罩。

## 安装

1. 先把 LiteLoaderQQNT 装到 QQ 9.9.37 上（需要文件校验绕过，否则改 `package.json` 会被 `error code v2:-8` 拦下）；
2. 把本仓库整个目录放到：

```
<QQ安装目录>/versions/<版本>/resources/app/LiteLoaderQQNT/plugins/liuli-dsh-theme/
```

3. 重启 QQ，设置 → 琉璃 里配置壁纸与配色。

目录名必须是 `liuli-dsh-theme`（与 `manifest.json` 的 `slug` 一致），否则 `local://profile/plugins/<slug>/assets/` 的样式/图片会 404。

## 已知限制

- 只在 9.9.37-54395 实测；同系列小版本大概率通用。
- 气泡与头像的 4px 间距是肉眼调的值，觉得太紧可以把 `assets/bubbles.css` 里两处 `4px` 改回 `6px/8px`。
- 空会话面板改成 `no-drag` 后，不能再用空聊天区拖动窗口，标题栏仍可拖。
- 剩余模糊为 9–10px，核显在 2K 以上窗口仍有成本，可在 设置 → 琉璃 → 外观 里继续调低。
- 列表滑翔高亮依赖 `pointerover/pointerout`，在 `-webkit-app-region: drag` 区域内不会触发（列表区本身不是 drag 区）。

## 上游与许可

- 设计与实现：LilycleHeart，MIT License；
- 本仓库只是针对 QQNT 9.9.37 的兼容性与性能补丁，未改变原主题的视觉设计。
