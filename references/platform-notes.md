# 站点机制、操作片段与故障对照

适用平台：超星泛雅 / 国科大在线（`mooc.mooc.ucas.edu.cn`、`mobilelearn.mooc.ucas.edu.cn`、
`d.mooc.ucas.edu.cn`、`passport.mooc.ucas.edu.cn`）。验证环境为 Windows + Codex 内置浏览器（`type: "iab"`）。

## 1. URL 模板

所有课程参数（`courseid` / `clazzid` / `cpi` / `enc` / `openc` / `t`）都直接从用户给的课程页 URL 复制。

```
# 教师课程首页（「我教的课」里点开某门课后的地址）
https://mooc.mooc.ucas.edu.cn/mooc2-ans/mooc2-ans/mycourse/tch
  ?courseid=<课程>&clazzid=<班级>&cpi=<...>&enc=<...>&t=<...>&pageHeader=-1&v=2&hideHead=0&perspectiveType=

# 作业列表（点顶部「作业」后 pageHeader=6，内容在 iframe 里加载）
https://mooc.mooc.ucas.edu.cn/mooc2-ans/work/list
  ?courseid=<课程>&clazzid=<班级>&courseId=<课程>&classId=<班级>&clazzId=<班级>
  &cpi=<...>&enc=<...>&openc=<...>&t=<...>&ut=t

# 某次作业的批阅页（<workid> 来自作业列表里的 div.work<workid>）
https://mooc.mooc.ucas.edu.cn/mooc2-ans/work/mark
  ?courseid=<课程>&clazzid=0&id=<workid>&cpi=<...>&evaluation=0&from=&v=0
  &prePageNum=1&prePageSize=12&topicid=0&perspectiveType=0

# 导出产物直链（一次性令牌，从「下载中心」现取）
https://d.mooc.ucas.edu.cn/workzip/<fid>/<courseid>/<clazzid>/<hash>/attachment/<clazzid>_<id>.zip
  ?_enc=<token>&_t=<ts>&fn=<URL 编码的压缩包名>
```

## 2. DOM 标识

| 用途 | 选择器 / 说明 |
|---|---|
| 顶部导航菜单项 | 无障碍树里的 link：「班级活动 / 章节 / 资料 / 通知 / 讨论 / 题库 / **作业** / 考试 / 统计 / 管理 …」 |
| 作业列表所在 iframe | `#frame_content-zy` |
| 作业列表行 | `div.work<workid>`，行内含标题（如「第二次作业」）与「批阅」链接 |
| 下载中心浮层 | `div.downloadcenter`（课程首页，不在作业页） |
| 导出附件弹窗 | `div#downWorkAttachment`（平时 `display:none`） |
| 导出弹窗的选项 | `#downWorkAttachment .export-flexBox .grade_check`，选中项 class 含 `grade_checked` |
| 导出弹窗确定按钮 | `#downWorkAttachment .confirmDown`（`onclick="checkPacking(1)"`） |
| 同页其他隐藏层 | `#exportWorkPop`、`#signaturePop`、`#markScore`、`#rebackPop`、`#workpop` 等 |

导出弹窗三个选项的含义：

| `data` | 含义 | 产物 |
|---|---|---|
| `0` | 导出完整答题记录 | 学生作答 + 教师批改 + 提交附件 |
| `2` | 仅导出文档留痕批注 | 教师批注附件 |
| `1` | **导出提交附件** | **只含学生提交附件的压缩包（本流程要的）** |

默认选中 `data="1"`。若被改动，点击含「导出提交附件」文案的元素切回即可。

## 3. 浏览器操作片段（cua_repl + Playwright）

```js
// 绑定
const tabs = await cua.listTabs();
globalThis.tab = await cua.getTab(tabs[0].id, { browser: "1" });

// 未登录时：显示浏览器并保住标签页，交给用户登录
await (await agent.browsers.get("1")).capabilities.get("visibility").set(true);
await tab.markHandoff();

// 打开目标作业的批阅页（推荐方式）
await tab.goto(MARK_URL);
await tab.getAXState();

// 打开「更多」→「导出作业附件」
await tab.click(MORE_INDEX);
await tab.getAXState();              // 读出「导出作业附件」的新 index
await tab.click(EXPORT_ATTACH_INDEX);

// 确认选中的是「导出提交附件」（data=1）
const sel = await tab.playwright.evaluate(() => {
  const el = document.getElementById('downWorkAttachment');
  return {
    display: getComputedStyle(el).display,
    opts: Array.from(el.querySelectorAll('.export-flexBox .grade_check'))
               .map(s => ({ data: s.getAttribute('data'), cls: s.className }))
  };
});

// 点确定
await tab.playwright.locator('#downWorkAttachment .confirmDown').click({ timeoutMs: 8000 });

// 回课程首页打开「下载中心」，轮询到不再有「导出中」
await tab.goto(COURSE_TCH_URL);
await tab.click(DOWNLOAD_CENTER_INDEX);
let txt = '';
const deadline = Date.now() + 300000;
while (Date.now() < deadline) {
  txt = await tab.playwright.evaluate(() => document.body.innerText.replace(/\s+/g, ' '));
  const seg = txt.slice(txt.indexOf('下载中心'));
  if (seg.includes('<第N次作业>') && !seg.includes('导出中')) break;
  await tab.playwright.waitForTimeout(8000);
}

// 取直链：getAXState 的树里，该条目下的 link 元素 Value 即 https://d.mooc.ucas.edu.cn/workzip/....zip
await tab.getAXState({ disableDiffing: true });
```

备用路径：从作业列表点「批阅」（AX 点击 iframe 内元素可能失败）。

```js
const fl = tab.playwright.frameLocator('#frame_content-zy');
await fl.locator(`a[href*="work/mark"][href*="id=${WORKID}"]`).first().click();
```

## 4. 压缩包结构

```
班级<班级号>-第N次作业(附件).zip
├── <学号>-<姓名>.zip      ← 每位已交学生一个；未交学生不出现
│   └── 学生提交的原始文件（通常 1 个 PDF，偶尔还有 jpg/其他）
└── ...
```

## 5. 故障对照表

| 现象 | 原因 | 处理 |
|---|---|---|
| 课程页跳到 `passport.mooc.ucas.edu.cn/login` | 自动化浏览器无登录态 | 显示窗口请用户登录，`markHandoff()` 保住标签页 |
| `Error: Browser is not available: chrome` / `edge` | 本地浏览器未接入 Codex | 改用 `iab`；或在目标机接入浏览器扩展/连接 |
| AX 点击 iframe 内「批阅」报 `No node found at given location` | index 失效或跨 iframe 点击 | 直接 `tab.goto(mark URL)` |
| 点「确定」后没有任何下载 | 设计如此，产物进「下载中心」 | 回课程首页打开下载中心 |
| 单次 JS 调用超时，之后报 `tab is not defined` | 工具 30 s 超时导致 JS 会话重置 | 重新 `listTabs()` + `getTab()`；长等待切成多段 |
| `window.checkPacking` 为 `undefined` | 页面脚本在隔离上下文 | 正常现象，别调用它，直接点按钮 |
| 用 `querySelectorAll('*')` 找不到中文文案 | 文本节点里混有 `<b>` 说明文字 | 用无障碍树或 `innerText` 定位 |
| `document.querySelector('.downloadContent a')` 查不到 | 该浮层内容不在常规 DOM 查询范围 | 从 `getAXState()` 的 link Value 读链接 |
| 直链下载 403 / 失败 | `_enc`、`_t` 令牌过期 | 重新打开「下载中心」，重新取一次链接 |
| 终端下载报网络错误 | 受限沙箱 | 以 `require_escalated` 重跑并说明用途 |
| 写入桌面或非系统盘被拒 | 工作区外写入 | 以 `require_escalated` 重跑 |
| 学生目录名不符合「学号-姓名」 | 工号或特殊学号（如 `2026E8004584031`） | 按第一个 `-` 切分，规则不变 |
| 某位学生只交了非目标格式 | 提交内容混装（如 jpg） | 按用户要求决定是否补导，并在汇报里点明 |

## 6. 只读性说明

整个流程对课程站点只做「查看 + 创建一次导出任务」，不会改成绩，不会提交或打回学生作业。
若还要清理「下载中心」里的历史导出记录，属于额外的删除操作，需另行向用户确认。
