# MMD Dance TD 模组分析笔记

> 分析时间 2026-11-23
> 目标文件: mdR_Anims_Base + MMD Dance Part3-1/3-2/3-3

---

## 一、模组架构（四个 VPK 的分工）

| VPK | 角色 | 内容 |
|---|---|---|
| **mdR_Anims_Base**（骨架） | 给每个生还者替换 `gestures_*.mdl` | 原版角色模型上**加 6 个 slot 的 animation set**（slot_001/002/003/011/031/032），是所有动作的底层承载 |
| **MMD Dance Part3-1** | 动画包 slot 001/002/003 | `models/mdreanims/<角色>_slot_<N>.ani` + `.mdl` + 脚本 + clientmenu + autoexec.cfg |
| **MMD Dance Part3-2** | 动画包 slot 011/031/032 | 只有 `.ani`（mdl 在 base 里） |
| **MMD Dance Part3-3** | 音乐包 | 61 个 mp3: `sound/music/flu/d01.mp3` ~ `d61.mp3` |

脚本入口:
- `director_base_addon.nut` 只有一行 `IncludeScript("dance_script")`
- 导演自动加载 → 读 `dance_script.nuc`（加密过，已解密为 `dance_script_decrypted.nut`）
- 另 IncludeScript 了 `dance_list.nut` 定义 `actionList`

---

## 二、跳舞逻辑完整流程

入口在 `dance_script_decrypted.nut` 第 4322 行: `OnGameEvent_player_say`

命令格式:
```
!d <角色代号> <动作名> [0|1]      // 单人
!2d <r1> <r2> <动作名> [0|1]     // 双人
!3d / !4d / !5d / !6d / !7d / !8d // 多人
!sd                               // 停止
!prev / !next                     // 循环切舞
```

角色代号：b=Bill z=Zoey f=Francis l=Louis n=Nick r=Rochelle c=Coach e=Ellis

### 核心函数链路（以 StartAnimation 为例，行 423-554）

1. `GetPlayerLookPos(player)` — 射线取玩家瞄准的地面点
2. `SpawnEntityFromTable("commentary_dummy", { model, origin=瞄准点, angles=反朝向 })`
   — 在那里 spawn 一个解说用假人（关键 trick：不是改真人，是原地生成 dummy）
3. `DanceModel.LookupSequence(actionString)` — 按名字查 sequence，找不到报 Error 然后删 dummy
4. `EntFire(danceModel, "SetAnimation", actionString)` — 直接切 sequence
5. 可选相机: spawn `prop_dynamic`（Introcam.mdl）+ `point_viewcontrol_multiplayer`
   → 把所有玩家 teleport 到 x=−9999 隐蔽起来 → 切到 dummy 视角（fov 55）
6. `EmitAmbientSoundOn("music/flu/" + actionString + ".mp3", ...)` — 播音乐（mp3 路径和动作名直接绑定）
7. `DoEntFire("!self", "RunScriptCode", "dance.stop()", 序列时长, ...)` — 自动停止
8. `dance.stop()`: Kill dummy/prop/viewcontrol，把玩家 teleport 回来，关音乐

### 多人队形布局

- **双人**: `AD_vec.Scale(±20)` 左右各 20 单位
- **三人**: 中间站位 + `AD_vec.Scale(±20) + WS_vec.Scale(30)` 前排 2、后排 1
- **四到八人**: 递增的 AD_vec / WS_vec 偏移（硬编码几何布局，不是真舞蹈同步）

辅助函数:
- `VectorFromQAngle()` — 角度转向量
- `ReturnADWS(look_angle)` — 返回左右/前后方向向量表

---

## 三、舞蹈名 vs slot vs sequence 的关系

`dance_list.nut` 里定义:
```squirrel
actionList <-[
    "d01","d02",..."d50",
    "d51","d52",..."d61"
]; // 单人舞蹈动作
```

**这些就是 mdl 里 sequence 的名字**。`LookupSequence("d01")` 按字符串在 mdl 里找 sequence。

原始作者的工作流:
1. 在 base 的 gestures mdl 里预定义 6 个 slot
2. 每个 slot 里嵌了 61 个 sequence（d01~d61）
3. Part3-1/Part3-2 的 `.ani` 是动画片段，L4D2 会合并同目录 .ani 进 mdl
4. Part3-3 的 mp3 按同一命名规则放，脚本自动拼路径

clientmenu_dance.txt 只是 UI 糖: 每个选项拼 `say_team !d z d01` → 本质就是聊天命令。

---

## 四、如何新增舞蹈

### 情况 A: 新增已有 slot 上的新 sequence（d62/d63/...）

需要改 4 处:
1. **mdl 层**: Crowbar/GUIStudioMDL 打开 `gestures_*.mdl`，给每个 slot 加新 sequence
2. **ani 层**: `models/mdreanims/<角色>_slot_<N>.ani`（L4D2 自动合并）
3. **script 层**: `dance_list.nut` 的 actionList 追加 `"d62", "d63"`
4. **music 层**: `sound/music/flu/d62.mp3`, `d63.mp3`

### 情况 B: 新增整个 slot（slot_041）

先解包 base 的 gestures mdl，用 Blender/SMD 工具加 slot（需要懂 Source 引擎底层 animation set 定义）。之后同情况 A。

### 情况 C: 最简单 — 替换/覆盖现有 sequence

做一个新 VPK，里面塞新的 `models/mdreanims/<角色>_slot_001.ani` + 新 `d01.mp3`。
VPK 加载顺序靠字母序，放在 Part3 后面就会覆盖。**不需要动任何 nut 脚本**。

### 关键发现: 脚本本身已经是可扩展的

Nut 脚本直接接受任意 action 字符串 → `LookupSequence` 按名字查。
也就是说: **只要你的新 sequence 叫 d62，命令 `!d z d62` 就已经能播**，一行脚本都不用改。actionList 只是给 prev/next 用的。

---

## 五、现有 test_plugin 的问题

`test_new_dance.sp` 想直接改真人的 `m_nSequence`，方向根本不对:

- 跳舞不是给真人改 sequence，是在**新 spawn 的 commentary_dummy** 上播
- 真人有 AI tick，改了 sequence 下一个 tick 就被恢复
- 完全没必要改 SourcePawn，Nut 脚本给了完整的命令格式扩展性

`director_testdance.nut` 的 hook thinker 也一样: 抓真人的 sequence 变化没用，因为 dummy 是新 entity。

---

## 六、建议下一步（未执行）

1. **先验证覆盖机制**: 做一个 dummy VPK 塞新 `d01.mp3` + 修改过的 `.ani`，进游戏看是否覆盖 — 最快入门
2. **抓一个 d01 的 .ani 样本**: 用 Crowbar 解 Part3-1 vpk，看 sequence 名是不是确实叫 `"d01"`，确认后 Blender 照格式做
3. **完全独立的自定义舞蹈系统**: 用 Nut 的 `SpawnEntityFromTable + commentary_dummy + EntFire("SetAnimation", ...)` 这套，直接忽略原作者的 .nuc 和 actionList

---

## 七、最终 MVP 源码（已落地）

文件位置:
- `h:\game workshop\L4D2\dance\mydance_main.nut` — 核心逻辑
- `h:\game workshop\L4D2\dance\director_mydance.nut` — 引擎入口（IncludeScript 主文件）

### 已补齐的原版底层坑（审查报告 6+1 条）

| 坑 | 修复 |
|---|---|
| commentary_dummy vs prop_dynamic | 用 commentary_dummy（原版专用于演示） |
| 主从假人分工 | MVP 单人阶段只 spawn 一个 dummy，后续加多人时处理 |
| 自动停止定时器 | DoEntFire + duration，:: 前缀绕开 RunScriptCode 作用域 bug |
| m_fEffects = 721 渲染修复 | NetProps.SetPropInt(dummy, "m_fEffects", 721) |
| logic_branch_bgm_relay 判空 | Entities.FindByName 先找再 ToggleTest |
| EntFire("SetAnimation") 不能直接 dummy.SetAnimation | 用 EntFire 调输入事件 |
| StopAmbientSoundOn 参数顺序 | (路径, 附着实体) 不能反 |
| SpawnEntityFromTable angles 必须 .ToKVString() | 避免 QAngle 对象静默失败 |
| LookupSequence == -1 守护 | sequence 不存在直接 Kill dummy |
| GetPlayerLookPos 不是内置函数 | 原样抄原版 TraceLine 实现 |
| RunScriptCode 全局函数作用域陷阱 | "::MyDanceCleanUp()" 强制根表查找 |
| Bot 排除 | IsPlayerABot(player) continue |

### 测试步骤

1. 把两个 .nut 复制到 `left4dead2/scripts/vscripts/` 或打包进 VPK
2. 关掉角色模型替换模组（或确保原版模型里有 d01 sequence）
3. 开官方单人战役地图（第三方图可能没有 logic_branch_bgm_relay，虽然我们判空了）
4. 控制台看有没有 `[MyDance] 框架加载成功!`
5. 聊天框输入 `!mytest`
6. 应该看到: 假人出现在准星位置 → 面向你 → 跳 d01 → 放音乐 → 时间到自动消失

### 聊天命令

| 命令 | 作用 |
|---|---|
| `!mytest` | 生成假人跳 d01 |
| `!mystop` | 强制清理（调试用） |

---

## 八、v2.0 重构: 4 模块解耦架构

### 架构图

```
OnGameEvent_player_say (入口)
  │ 解析命令 → DanceConfig.actions / DanceConfig.models
  ▼
DanceController (主体)
  ├─ GetPlayerLookPos
  ├─ SpawnEntityFromTable("commentary_dummy")
  ├─ LookupSequence 守护
  ├─ NetProps 721 渲染修复
  ├─ EntFire("SetAnimation")
  ├─ DoEntFire 定时器 (存在 dummy ScriptScope)
  ├─ ▶ MusicController.play()          [副体1]
  ├─ ▶ CameraController.setup()        [副体2]
  └─ ▶ LyricController.setup()         [副体3, 占位]

MusicController (副体1)
  ├─ precache(path) — IsSoundPrecached + PrecacheSound
  ├─ play() — EmitAmbientSoundOn(路径, 10, 100, 100, dummy)
  ├─ stopAll() — StopAmbientSoundOn + 恢复 BGM relay
  └─ _ensureBgmRelay() — 懒加载缓存 logic_branch_bgm_relay

CameraController (副体2)
  ├─ setup() — spawn prop_dynamic(Introcam.mdl) + viewcontrol
  │            严格顺序: SetParent → SetParentAttachment("cam") → Enable
  │            传送真人到 -9999 (bot 排除)
  └─ cleanup() — Disable viewcontrol → Kill prop+vc → 恢复玩家位置

LyricController (副体3)
  ├─ setup() — 占位空实现
  └─ cleanup() — 占位空实现

DanceConfig (配置表)
  ├─ models: { "z": "models/survivors/survivor_teenangst.mdl", ... } × 8 角色
  ├─ actions: { "d01": { seq: "d01", music: "music/flu/d01.mp3" }, ... }
  ├─ camera: { enabled, model, fov, spawnflags }
  ├─ music:  { enabled, volume, distance, falloff }
  ├─ dummy:  { lookAtPlayers, effectsFix }
  └─ commands: { "!dance": "start", "!mystop": "stop_all", ... }
```

### 为什么解耦？

1. **配置即扩展**：新增舞蹈只改 `DanceConfig.actions` 表，一行 entry = 一个新舞蹈，不用改主逻辑
2. **模块可开关**：相机/音乐/歌词各有 `enabled` 开关，MVP 阶段默认关相机
3. **副体独立**：MusicController 可以被其他场景复用（比如单独播音乐），CameraController 以后支持更多相机方案
4. **占位清晰**：LyricController 先占位，以后 SourceMod UI 或 VScript Panel 都可以往里填

### 聊天命令 (v2.0)

| 命令 | 作用 |
|---|---|
| `!dance <代号> <动作>` | 单人，角色代号 (z/b/l/f/n/r/e/c)，动作名 = DanceConfig.actions key |
| `!dancecam <代号> <动作>` | 开启相机的单人 (无视 DanceConfig.camera.enabled) |
| `!mytest` | 兼容旧版 = `!dance z d01` |
| `!mystop` | 强制停止所有 (调试用) |

### 新增自定义舞蹈的 3 步

1. 确保 mdl 里有对应的 sequence（用 Crowbar/GUIStudioMDL 加，或 .ani 提供动画数据）
2. 确保 VPK 里有对应的 mp3 放在 `sound/` 下
3. 在 DanceConfig.actions 里加一行:
   ```squirrel
   "my_custom_dance" : { seq = "myseq_name", music = "music/custom/my_dance.mp3" },
   ```
4. 进游戏: `!dance z my_custom_dance`

### v2.0 新增的原版细节

| 细节 | 实现位置 |
|---|---|
| GetSurvivorModel 映射 (8 角色代号→固定模型路径) | DanceConfig.models |
| Introcam.mdl 路径 = `models/DanceCam/Introcam.mdl` | DanceConfig.camera.model |
| viewControl spawnflags=5, fov=55 (原版硬编码) | DanceConfig.camera |
| viewControl 必须 SetParent + SetParentAttachment("cam") 挂相机骨骼 | CameraController.setup |
| RunScriptCode 回调存 dummy ScriptScope 闭包 | DanceController.start |
| 最后一个 dummy 结束才触发全量 cleanup (副体1+2+3) | DanceController._onAutoStop |
| 相机 setup 失败自动回滚 | DanceController.start (CameraController.cleanup 提前调) |

### 测试 checklist (v2.0)

- [ ] console 有 `[MyDance] 框架加载成功!` + DanceConfig 注册日志
- [ ] `!mytest` → Zoey dummy spawn + 播 d01 + 自动消失
- [ ] `!dance b d02` → Bill dummy spawn + 播 d02
- [ ] `!dance my_custom` → 如果 DanceConfig.actions 里没有，报 "未知动作"
- [ ] dummy 全黑？检查 NetProps 721
- [ ] dummy 背对？检查 angles +180
- [ ] 音乐无声？检查 musicPath 路径 + IsSoundPrecached
- [ ] 相机开启后玩家卡虚空？检查 CameraController.cleanup 是否被触发
