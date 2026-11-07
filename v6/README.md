# v6 · Campground & Lake（polyfork kit 复现）

把 [polyfork 的 Campground & Lake kit](https://polyfork.dev/kit/campground-lake-ad32b0) 那张
单文件场景 GLB（19.87 MB / 533 mesh / 162k tris）在 Godot 4.7 里跑起来，默认视角、背景、
光照都与该页 three.js 观看器逐项对齐。

叠图比对（1246×956，同机同尺寸）：`mean|diff| = 3.53/255`（1.4%），模型区三通道比值
`0.997 / 1.004 / 1.005`，说明亮度与色偏基本一致，残差集中在抗锯齿边缘。

![默认视角 1246×956，`pwsh tools/shot.ps1` 出图](docs/img/campground-lake.png)

## 跑起来

新克隆下来先导入一次 GLB、再跑一次拆件器（`assets/parts/` 是生成物，不入库）：

```powershell
godot --headless --path v6 --import                          # 没有 .godot/imported 时 GLB 载不进来
godot --headless --path v6 -s res://tools/split_parts.gd     # 拆成 174 件，约 17 MB
```

```powershell
pwsh v6/tools/run.ps1          # 开窗：左键拖动环绕、滚轮缩放（朝光标放大）、方向键微调、+/- 缩放、R 复位
                               # 滚轮每格 ×0.85；Shift 微调 ×0.97；Ctrl 快速 ×0.60；范围 0.6~450 m
                               # 拖动有地形高度兜底 + 8° 俯角硬下限，不会钻到岛下面透底
pwsh v6/tools/shot.ps1         # 出静帧 → .run/v6-shots/kit.png
pwsh v6/tools/shot.ps1 -DumpShadow   # 顺带把接触阴影的烘培贴图也存下来
```

地图编辑器（拖动摆放、旋转缩放、增删复制、存 `map.json`）：

```powershell
pwsh v6/tools/edit.ps1                 # 打开 data/maps/campground_edit.json
pwsh v6/tools/edit.ps1 -Map my_map.json
```

Web（HTML5 / WebAssembly，纯静态文件）：

```powershell
pwsh v6/tools/build_web.ps1            # → dist/web/（首次缺 assets/parts 会自动拆件）
python v6/tools/serve_web.py           # → http://127.0.0.1:5173（dev 隧道 https://dev.wulie.tech）
```

浏览器里 Web 平台自动用 gl_compatibility（WebGL2），平台差异、线程开关和部署注意
见 [docs/web.md](docs/web.md)。

改个别模型：把 `assets/parts/<变体>.tscn` 复制到 `assets/parts_over/` 同名再改（或放同名 `.glb`），
加载时覆盖生效，不动 GLB、不重跑拆件器。详见 [docs/地图与模型.md](docs/地图与模型.md)。

交互自检（把拖动/滚轮灌成本地事件，核对相机按 OrbitControls 规则动）：

```powershell
godot --path v6 --resolution 1246x956 -- --selftest
# SELFTEST yaw 0.6100→-0.0181 (Δ-0.6174, 期望≈-0.628)  yaw_ok=true zoom_in_ok=true
```

## 参数对照（页面 viewer.js → 这里 data/look.json）

| 项 | 页面 | 这里 | 说明 |
|---|---|---|---|
| 相机 | `PerspectiveCamera(38, 1, 0.01, 200)` | `fov 38`，`near = R*0.012`，`far = max(200, R*30)` | near/far 也按半径跟 |
| 取景距离 | `d = R / sin(fov/2) * 0.525` | 同式，`cam.fit = 0.525` | R = AABB 半对角线 = 69.153 m，d = 111.513 m |
| 可缩放范围 | OrbitControls 0.35d~2.5d（39~279 m） | `cam.min_distance 0.6` / `max_distance 450` | 页面只给到 39 m，看不了细节；这里给到能贴脸 |
| 俯角/方位 | `pitch 17.8°`，`yaw 0.61` | 同 | 位姿公式与 `camera.position.set` 逐字一致 |
| 背景 | canvas 上的一层 CSS 径向渐变 | `bg_gradient`（按 CSS 公式逐像素生成） | 见下 |
| 半球光 | `HemisphereLight(0xffffff, 0xb8b0a4, 1.15)` | 渐变天光贴图 + `AMBIENT_SOURCE_SKY` | 亮度 = 1.15/π |
| 主光 | `DirectionalLight(0xfff2e0, 2.4) @ (4,7,5)` | `energy 2.4/π = 0.7639` | Godot 没有 1/π，见标定 |
| 补光 | `DirectionalLight(0xdfe8ff, 0.9) @ (-5,4,-6)` | `energy 0.9/π = 0.2865` | 同上 |
| 阴影 | PCFSoft 4096、`bias 0`、`normalBias` 按 texel | 单向正交阴影、`bias 0.02`、`normal_bias 1.0`、`blur 1.0` | |
| 地面接触影 | `ShadowMaterial(opacity 0.18)` 圆盘 | 启动时烘一张正交阴影贴图贴回地面 | `contact_shadow` |
| 色调映射 | 无（NoToneMapping） | `TONE_MAPPER_LINEAR`，exposure 1.0 | 不开 glow/SSAO/雾 |

所有数字都在 `v6/data/look.json`，改参数不用改代码；`--look=res://data/look_xxx.json` 可以
做 A/B。想看更大一点就调 `cam.fit`（页面默认 0.525，调到 0.45 大约放大 1.17 倍）。

## 三个必须知道的实测结论

1. **Godot 的平行光没有 1/π**。albedo=0.5 的白板在 `energy=1` 下输出 0.5（线性），
   three.js 是 `albedo/π * intensity`。所以页面上的强度都要除以 π 才等价。
2. **Godot 的 Color 属性是 sRGB**（`gray 0.5 → 线性 0.212`）。`light_color` /
   `background_color` / `albedo_color` 都别手动再转一次，否则颜色发灰发暗。
3. **glTF 导入默认不开 `vertex_color_use_as_albedo`**（本 GLB 536/536 个 mesh 都是 false）。
   这套 kit 的颜色全在 COLOR_0 顶点色里，不打开就整片白。

## 背景那层渐变

页面舞台是 `rgb(234,241,254)`，但 canvas 自己是 alpha 透明的，真正看到的是 canvas 上的
CSS：`radial-gradient(120% 130% at 32% 18%, #fff 0%, #eef2f7 55%, #dfe6ef 100%)`。
这里用 `BG_CANVAS` + 一张按同一公式生成的贴图复现，实测与页面逐像素差 0~2。

## 目录

```
v6/
  project.godot            1246x956，Forward+，MSAA 4x，4096 方向光阴影
  scenes/main.tscn         观看器：只有一根 Node3D + main.gd（场景由代码搭，便于调参）
  scenes/editor.tscn       地图编辑器入口（scripts/editor.gd 继承 main.gd）
  scripts/main.gd          载地图、包围盒、环境/光/相机、轨道相机、接触阴影烘培、出静帧
  scripts/editor.gd        编辑器：选中/拖动/旋转/缩放/增删复制/撤销/存盘 + HUD
  scripts/map_world.gd     地图 JSON 读写、part 解析（含 parts_over 覆盖）、拼装
  shaders/hemi_sky.gdshader      半球光等价物
  shaders/ground_shadow.gdshader 接触阴影的地面接影
  data/look.json           全部可调参数（相机/背景渐变/光/接触阴影）
  data/maps/campground.json        拆件器生成的默认地图（174 条）
  data/maps/campground_edit.json   编辑器保存出来的地图
  assets/kit_campground_lake/…glb  原始场景（19.87 MB）
  assets/parts/<变体>.tscn         拆件器生成物（174 个，17 MB，gitignore）
  assets/parts_over/               人工覆盖件（优先于 parts/）
  tools/                   运行 / 出静帧 / 编辑器 / 拆件 / 校验 / 标定 / 拼图比对
  tools/build_web.ps1      Web 出包（import → 缺件时拆件 → export-release）
  tools/serve_web.py       本地静态服务器（.wasm MIME + COOP/COEP，默认 5173）
  docs/web.md              Web 构建 / 预览 / 部署与 Compatibility 差异
```

工作产物（截图、appdata、日志）都落在仓库根的 `.run/` 下，不进库。

## 本机实测

GTX 1050 Ti / 1246×956 / 关 vsync：`avg 11.8~12.4 ms`（80~85 fps），`draw_calls 1078`
（537 个 mesh × 主渲染 + 阴影 pass）。整张 GLB 与 174 件拼装两条路径实测同速；
早期一次 6.74 ms 的读数没复现出来（窗口是否在前台会影响），不作为结论。
没做合并/批处理，先把效果对齐。

## 手机

`pwsh v6/tools/build_apk.ps1` 出 APK（包名 `hometown.wulie.tech`，arm64），
`pwsh v6/tools/install_apk.ps1` 装机并拉起。手机上：单指拖 = 环绕，双指捏合 = 缩放，
双指一起拖 = 平移。触摸是自己处理的（`input_devices/pointing/emulate_mouse_from_touch=false`）。

## 人物

4 个角色（护林员 / 提手电的小孩 / 背包客 / 钓鱼客）会动：在出生点附近游走、到点停下、
步态与呼吸是程序化的（GLB 里没有动画片段）。`--no-actors` 关掉，`--sim-t=秒` 推进时间。
细节见 [docs/地图与模型.md](docs/地图与模型.md)。

## 性能（同机同日实测）

| 在哪 | 分辨率 | 帧时 | fps | draw calls |
|---|---|---|---|---|
| 手机 vivo V2458A（Mali-G925） | 2800×1260 | 16.6 ms | 60（vsync 锁） | 1074 |
| 手机（wm size 降到 1/4 像素） | 1400×630 | 8.38 ms | 119 | 1074 |
| 桌面 GTX 1050 Ti | 1246×956 | 5.88 ms | 170 | 1078 |

瓶颈是 **draw call**（174 个 part 各一套网格、没合批），不是像素也不是人物/阴影
（人物 −0.15 ms、接触阴影 −0.32 ms）。详细分项与优化顺序见
[docs/性能.md](docs/性能.md)。debug 包每 3 秒往 logcat 打一行 PERF ...，
手机上 `adb logcat -s godot` 就能看。

## 已知差异

- 阴影过滤算法不同（three.js PCFSoft vs Godot 的 soft shadow filter），边缘柔和度略有差别。
- 页面在裸 GLB 上还叠了 `ao-core.mjs` / `looks.mjs` 这类运行时效果，默认态没启用，这里也没加。
- GLB 自带 36 个 skin（水面、灯串等可动件），页面靠 .mjs 驱动；本工程暂无动画，静态显示。
- Web 用 Compatibility（WebGL2）渲染，阴影/抗锯齿与桌面 Forward+ 略有差别，见 [docs/web.md](docs/web.md)。
